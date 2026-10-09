// MARK: - TimerTables

/// The rows the timer touches, held in memory. Reference semantics of `TimerChange` for all stores.
public struct TimerTables: Hashable, Sendable {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  public var entries = [EntryID: TimeEntry]()
  public var segments = [SegmentID: Segment]()
  public var globalPauses = [GlobalPauseID: GlobalPause]()
  public var idleEvents = [IdleEventID: IdleEvent]()
  public var heartbeat: Timestamp?

  /// Applies all changes or none.
  public mutating func apply(_ changes: [TimerChange]) throws {
    var copy = self
    for change in changes {
      switch change {
      case .entry(let before, let after):
        // Mirrors NOT NULL CHECK (weight > 0) of time_entry; SQLite stores NaN as NULL.
        if let after, !(after.weight > 0) { throw TimerStoreError.invalidValue }
        try Self.apply(before, after, to: &copy.entries)
        if before != nil, after == nil, let id = before?.id {
          // Mirrors ON DELETE CASCADE of segment.entry_id.
          copy.segments = copy.segments.filter { $0.value.entryID != id }
        }

      case .segment(let before, let after):
        if let entryID = after?.entryID, copy.entries[entryID] == nil {
          throw TimerStoreError.conflict
        }
        // Mirrors CHECK (end_at > start_at) of segment.
        if let after, let end = after.end, end <= after.start { throw TimerStoreError.invalidValue }
        try Self.apply(before, after, to: &copy.segments)

      case .globalPause(let before, let after):
        try Self.apply(before, after, to: &copy.globalPauses)

      case .idleEvent(let before, let after):
        try Self.apply(before, after, to: &copy.idleEvents)
      }
    }
    self = copy
  }

  public func snapshot() -> TimerSnapshot {
    let active = entries.values
      .filter { $0.deletedAt == nil && $0.state != .stopped }
      .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    let byEntry = Dictionary(grouping: segments.values, by: \.entryID)
    let activeEntries = active.map { entry in
      let segments = byEntry[entry.id] ?? []
      let closed = segments.compactMap { segment in segment.end.map { $0.seconds(since: segment.start) } }
      return ActiveEntry(
        entry: entry,
        openSegment: segments.first(where: \.isOpen),
        closedDuration: closed.reduce(0, +),
        lastEnd: segments.compactMap(\.end).max(),
      )
    }
    let openPause = globalPauses.values
      .filter { $0.resumedAt == nil }
      .max { $0.pausedAt < $1.pausedAt }
    let pending = idleEvents.values
      .filter { $0.resolution == nil }
      .sorted { $0.start < $1.start }
    return TimerSnapshot(
      entries: activeEntries,
      globalPause: openPause,
      pendingIdleEvents: pending,
      lastHeartbeat: heartbeat,
    )
  }

  // MARK: Private

  private static func apply<Row: Identifiable & Equatable>(
    _ before: Row?,
    _ after: Row?,
    to rows: inout [Row.ID: Row],
  ) throws {
    guard let id = before?.id ?? after?.id else { return }
    guard rows[id] == before else { throw TimerStoreError.conflict }
    rows[id] = after
  }

}

// MARK: - InMemoryTimerStore

/// A `TimerStore` for tests and SwiftUI previews.
public actor InMemoryTimerStore: TimerStore {

  // MARK: Lifecycle

  public init(tables: TimerTables = TimerTables()) {
    self.tables = tables
  }

  // MARK: Public

  public private(set) var tables: TimerTables

  public func snapshot() -> TimerSnapshot {
    tables.snapshot()
  }

  public func update<T: Sendable>(
    _ body: @Sendable (TimerSnapshot) throws -> TimerUpdate<T>
  ) throws -> TimerCommit<T> {
    let update = try body(tables.snapshot())
    try tables.apply(update.changes)
    sequence += 1
    return TimerCommit(value: update.result, snapshot: tables.snapshot(), sequence: sequence)
  }

  public func latest() -> TimerCommit<Void> {
    TimerCommit(value: (), snapshot: tables.snapshot(), sequence: sequence)
  }

  public func recordHeartbeat(_ timestamp: Timestamp) {
    tables.heartbeat = timestamp
  }

  // MARK: Private

  private var sequence = 0

}
