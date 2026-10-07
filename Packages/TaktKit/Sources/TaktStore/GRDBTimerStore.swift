import GRDB
import TaktCore

/// `TimerStore` on SQLite. Each `update` is one write transaction.
public struct GRDBTimerStore: TimerStore {
    static let heartbeatKey = "engine.heartbeat"

    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func snapshot() async throws -> TimerSnapshot {
        try await database.writer.read { db in try Self.snapshot(db) }
    }

    public func update<T: Sendable>(
        _ body: @Sendable (TimerSnapshot) throws -> TimerUpdate<T>
    ) async throws -> T {
        try await database.writer.write { db in
            let update = try body(try Self.snapshot(db))
            for change in update.changes {
                try Self.apply(change, db)
            }
            return update.result
        }
    }

    public func recordHeartbeat(_ timestamp: Timestamp) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)",
                arguments: [Self.heartbeatKey, String(timestamp.milliseconds)]
            )
        }
    }

    // MARK: Reading

    static func snapshot(_ db: Database) throws -> TimerSnapshot {
        let entries = try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM time_entry
                WHERE deleted_at IS NULL AND state != 'stopped'
                ORDER BY created_at, id
                """
        ).map(TimeEntry.init(row:))

        var segmentsByEntry: [EntryID: [Segment]] = [:]
        if !entries.isEmpty {
            let ids = entries.map(\.id.uuidString)
            let placeholders = databaseQuestionMarks(count: ids.count)
            let segments = try Row.fetchAll(
                db,
                sql: "SELECT * FROM segment WHERE entry_id IN (\(placeholders))",
                arguments: StatementArguments(ids)
            ).map(Segment.init(row:))
            segmentsByEntry = Dictionary(grouping: segments, by: \.entryID)
        }

        let active = entries.map { entry in
            let segments = segmentsByEntry[entry.id] ?? []
            let closed = segments.compactMap { segment in segment.end.map { $0.seconds(since: segment.start) } }
            return ActiveEntry(
                entry: entry,
                openSegment: segments.first(where: \.isOpen),
                closedDuration: closed.reduce(0, +)
            )
        }

        let globalPause = try Row.fetchOne(
            db,
            sql: "SELECT * FROM global_pause WHERE resumed_at IS NULL ORDER BY paused_at DESC LIMIT 1"
        ).map(GlobalPause.init(row:))

        let pendingIdle = try Row.fetchAll(
            db,
            sql: "SELECT * FROM idle_event WHERE resolution IS NULL ORDER BY start_at"
        ).map(IdleEvent.init(row:))

        let heartbeat = try String.fetchOne(
            db, sql: "SELECT value FROM setting WHERE key = ?", arguments: [heartbeatKey]
        ).flatMap(Int64.init).map(Timestamp.init(milliseconds:))

        return TimerSnapshot(
            entries: active,
            globalPause: globalPause,
            pendingIdleEvents: pendingIdle,
            lastHeartbeat: heartbeat
        )
    }

    // MARK: Writing

    static func apply(_ change: TimerChange, _ db: Database) throws {
        switch change {
        case .entry(let before, let after): try apply(before, after, db)
        case .segment(let before, let after): try apply(before, after, db)
        case .globalPause(let before, let after): try apply(before, after, db)
        case .idleEvent(let before, let after): try apply(before, after, db)
        }
    }

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
                let columns = after.columns.sorted { $0.key < $1.key }
                let names = columns.map(\.key).joined(separator: ", ")
                try db.execute(
                    sql: "INSERT INTO \(table) (\(names)) VALUES (\(databaseQuestionMarks(count: columns.count)))",
                    arguments: StatementArguments(columns.map(\.value))
                )
            case (_?, let after?):
                let columns = after.columns.filter { $0.key != "id" }.sorted { $0.key < $1.key }
                let assignments = columns.map { "\($0.key) = ?" }.joined(separator: ", ")
                try db.execute(
                    sql: "UPDATE \(table) SET \(assignments) WHERE id = ?",
                    arguments: StatementArguments(columns.map(\.value) + [id])
                )
            }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY {
            // A missing parent row, e.g. a segment of an entry that no longer exists.
            throw TimerStoreError.conflict
        }
    }
}
