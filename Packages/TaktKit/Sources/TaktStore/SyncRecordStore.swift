import Foundation
import GRDB
import TaktCore

extension SyncRecord: TableRow {
    static let table = "sync_record"
    var rowID: String { id.uuidString }

    init(row: Row) throws {
        self.init(
            id: try row.id("id"),
            entryID: try row.id("entry_id"),
            workItemLinkID: try row.id("work_item_link_id"),
            localDay: row["local_day"],
            field: row["field"],
            deltaSeconds: row["delta_seconds"],
            status: try row.enumValue("status"),
            adoRevision: row["ado_rev"],
            error: row["error"],
            createdAt: row.timestamp("created_at"),
            syncedAt: row.optionalTimestamp("synced_at")
        )
    }

    var columns: [String: (any DatabaseValueConvertible)?] {
        [
            "id": id.uuidString, "entry_id": entryID.uuidString, "work_item_link_id": workItemLinkID.uuidString,
            "local_day": localDay, "field": field, "delta_seconds": deltaSeconds, "status": status.rawValue,
            "ado_rev": adoRevision, "error": error, "created_at": createdAt.milliseconds,
            "synced_at": syncedAt?.milliseconds,
        ]
    }
}

/// The local booking log (DO-24). Records are never deleted: they are the only history of bookings.
public struct SyncRecordStore: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func insert(_ record: SyncRecord) async throws {
        try await database.writer.write { db in
            let columns = record.columns.sorted { $0.key < $1.key }
            try db.execute(
                sql: """
                    INSERT INTO sync_record (\(columns.map(\.key).joined(separator: ", ")))
                    VALUES (\(databaseQuestionMarks(count: columns.count)))
                    """,
                arguments: StatementArguments(columns.map(\.value))
            )
        }
    }

    public func update(_ record: SyncRecord) async throws {
        try await database.writer.write { db in
            let columns = record.columns.filter { $0.key != "id" }.sorted { $0.key < $1.key }
            try db.execute(
                sql: "UPDATE sync_record SET \(columns.map { "\($0.key) = ?" }.joined(separator: ", ")) WHERE id = ?",
                arguments: StatementArguments(columns.map(\.value) + [record.id.uuidString])
            )
        }
    }

    /// All records of the entries, oldest first.
    public func records(for entries: [EntryID]) async throws -> [SyncRecord] {
        guard !entries.isEmpty else { return [] }
        return try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM sync_record WHERE entry_id IN (\(databaseQuestionMarks(count: entries.count)))
                    ORDER BY created_at
                    """,
                arguments: StatementArguments(entries.map(\.uuidString))
            ).map(SyncRecord.init(row:))
        }
    }

    /// All records of a local day (`YYYY-MM-DD`), including those of deleted entries.
    public func records(onDay localDay: String) async throws -> [SyncRecord] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM sync_record WHERE local_day = ? ORDER BY created_at", arguments: [localDay]
            ).map(SyncRecord.init(row:))
        }
    }

    public func pending() async throws -> [SyncRecord] {
        try await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM sync_record WHERE status = 'pending' ORDER BY created_at")
                .map(SyncRecord.init(row:))
        }
    }

    public func record(_ id: SyncRecordID) async throws -> SyncRecord? {
        try await database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM sync_record WHERE id = ?", arguments: [id.uuidString])
                .map(SyncRecord.init(row:))
        }
    }
}
