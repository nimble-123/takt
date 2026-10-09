import GRDB
import Synchronization
import TaktCore

/// `TimerStore` on SQLite. Each `update` is one write transaction.
public struct GRDBTimerStore: TimerStore {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

  public func snapshot() async throws -> TimerSnapshot {
    try await database.writer.read { db in try Self.snapshot(db) }
  }

  public func update<T: Sendable>(
    _ body: @Sendable (TimerSnapshot) throws -> TimerUpdate<T>
  ) async throws -> TimerCommit<T> {
    try await database.writer.write { db in
      let update = try body(try Self.snapshot(db))
      // Read before the changes: deleting an entry logs the segments it had (AZ-04).
      let log = try update.log.map { log in
        try SegmentChangeRecord.records(for: update.changes, log: log) { id in
          try Row.fetchAll(db, sql: "SELECT * FROM segment WHERE entry_id = ?", arguments: [id.uuidString])
            .map(Segment.init(row:))
        }
      } ?? []
      for change in update.changes {
        do {
          try Self.apply(change, db)
        } catch let error as DatabaseError
          where [.SQLITE_CONSTRAINT_CHECK, .SQLITE_CONSTRAINT_NOTNULL].contains(error.extendedResultCode)
        {
          // Same error as `InMemoryTimerStore`, not a raw database error. NOT NULL covers a NaN
          // weight, which SQLite stores as NULL.
          throw TimerStoreError.invalidValue
        }
      }
      for record in log {
        try record.insertRow(into: db)
      }
      // Writes are serialised, so the sequence follows the order of the commits.
      let sequence = writes.next()
      return TimerCommit(value: update.result, snapshot: try Self.snapshot(db), sequence: sequence)
    }
  }

  public func latest() async throws -> TimerCommit<Void> {
    // Read through the writer, so no write can commit between the read and the sequence.
    try await database.writer.write { db in
      TimerCommit(value: (), snapshot: try Self.snapshot(db), sequence: writes.current())
    }
  }

  public func recordHeartbeat(_ timestamp: Timestamp) async throws {
    try await database.writer.write { db in
      try db.execute(
        sql: "INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)",
        arguments: [Self.heartbeatKey, String(timestamp.milliseconds)],
      )
    }
  }

  // MARK: Internal

  /// Counts the writes of this store; shared by its copies.
  final class WriteCounter: Sendable {

    // MARK: Internal

    func next() -> Int {
      count.withLock { value in
        value += 1
        return value
      }
    }

    func current() -> Int {
      count.withLock { $0 }
    }

    // MARK: Private

    private let count = Mutex(0)
  }

  static let heartbeatKey = "engine.heartbeat"

  static func snapshot(_ db: Database) throws -> TimerSnapshot {
    let entries = try Row.fetchAll(
      db,
      sql: """
        SELECT * FROM time_entry
        WHERE deleted_at IS NULL AND state != 'stopped'
        ORDER BY created_at, id
        """,
    ).map(TimeEntry.init(row:))

    var segmentsByEntry = [EntryID: [Segment]]()
    if !entries.isEmpty {
      let ids = entries.map(\.id.uuidString)
      let placeholders = databaseQuestionMarks(count: ids.count)
      let segments = try Row.fetchAll(
        db,
        sql: "SELECT * FROM segment WHERE entry_id IN (\(placeholders))",
        arguments: StatementArguments(ids),
      ).map(Segment.init(row:))
      segmentsByEntry = Dictionary(grouping: segments, by: \.entryID)
    }

    let active = entries.map { entry in
      let segments = segmentsByEntry[entry.id] ?? []
      let closed = segments.compactMap { segment in segment.end.map { $0.seconds(since: segment.start) } }
      return ActiveEntry(
        entry: entry,
        openSegment: segments.first(where: \.isOpen),
        closedDuration: closed.reduce(0, +),
        lastEnd: segments.compactMap(\.end).max(),
      )
    }

    let globalPause = try Row.fetchOne(
      db,
      sql: "SELECT * FROM global_pause WHERE resumed_at IS NULL ORDER BY paused_at DESC LIMIT 1",
    ).map(GlobalPause.init(row:))

    let pendingIdle = try Row.fetchAll(
      db,
      sql: "SELECT * FROM idle_event WHERE resolution IS NULL ORDER BY start_at",
    ).map(IdleEvent.init(row:))

    let heartbeat = try String.fetchOne(
      db,
      sql: "SELECT value FROM setting WHERE key = ?",
      arguments: [heartbeatKey],
    ).flatMap(Int64.init).map(Timestamp.init(milliseconds:))

    return TimerSnapshot(
      entries: active,
      globalPause: globalPause,
      pendingIdleEvents: pendingIdle,
      lastHeartbeat: heartbeat,
    )
  }

  static func apply(_ change: TimerChange, _ db: Database) throws {
    switch change {
    case .entry(let before, let after): try apply(before, after, db)
    case .segment(let before, let after): try apply(before, after, db)
    case .globalPause(let before, let after): try apply(before, after, db)
    case .idleEvent(let before, let after): try apply(before, after, db)
    }
  }

  // MARK: Private

  private let database: AppDatabase
  private let writes = WriteCounter()

  /// Writes `after` only if the stored row equals `before`.
  private static func apply<Value: TableRow>(_ before: Value?, _ after: Value?, _ db: Database) throws {
    guard let id = before?.rowID ?? after?.rowID else { return }
    let table = Value.table
    let stored = try Row.fetchOne(db, sql: "SELECT * FROM \(table) WHERE id = ?", arguments: [id])
      .map(Value.init(row:))
    guard stored == before else { throw TimerStoreError.conflict }

    do {
      switch (before, after) {
      case (_, nil):
        try db.execute(sql: "DELETE FROM \(table) WHERE id = ?", arguments: [id])

      case (nil, let after?):
        try after.insertRow(into: db)

      case (_?, let after?):
        try after.updateRow(id: id, in: db)
      }
    } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY {
      // A missing parent row, e.g. a segment of an entry that no longer exists.
      throw TimerStoreError.conflict
    } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
      // Same error as `InMemoryTimerStore`: a second open segment of an entry (index segment_open).
      throw TimerStoreError.invalidValue
    }
  }
}
