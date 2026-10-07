import Foundation
import GRDB
import TaktCore

/// Read-only queries on entries and segments for the UI and analytics.
public struct EntryQueries: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func entry(_ id: EntryID) async throws -> TimeEntry? {
        try await database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM time_entry WHERE id = ?", arguments: [id.uuidString])
                .map(TimeEntry.init(row:))
        }
    }

    /// The most recently used distinct activities that are not running or paused, newest first (MB-05).
    public func recentDrafts(limit: Int) async throws -> [EntryDraft] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT title, project_id, task_id, category_id, work_item_link_id, MAX(updated_at) AS used_at
                    FROM time_entry
                    WHERE deleted_at IS NULL AND state = 'stopped'
                    GROUP BY title, project_id, task_id, category_id, work_item_link_id
                    ORDER BY used_at DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            ).map { row in
                EntryDraft(
                    title: row["title"],
                    projectID: try row.optionalID("project_id"),
                    taskID: try row.optionalID("task_id"),
                    categoryID: try row.optionalID("category_id"),
                    workItemLinkID: try row.optionalID("work_item_link_id")
                )
            }
        }
    }

    /// Segments of non-deleted entries overlapping `range`, with the entries' effective counting
    /// settings. Open segments end at `now`. Feed the result to `Allocation.allocate(_:in:)`.
    public func allocationInputs(
        in range: Range<Timestamp>, now: Timestamp, defaultMode: CountingMode
    ) async throws -> [Allocation.Input] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT s.start_at, COALESCE(s.end_at, :now) AS end_at, e.id,
                           COALESCE(e.counting_mode, :defaultMode) AS mode, e.weight
                    FROM segment s
                    JOIN time_entry e ON e.id = s.entry_id
                    WHERE e.deleted_at IS NULL
                      AND s.start_at < :rangeEnd
                      AND COALESCE(s.end_at, :now) > :rangeStart
                    ORDER BY s.start_at
                    """,
                arguments: [
                    "now": now.milliseconds,
                    "defaultMode": defaultMode.rawValue,
                    "rangeStart": range.lowerBound.milliseconds,
                    "rangeEnd": range.upperBound.milliseconds,
                ]
            ).map { row in
                Allocation.Input(
                    entryID: try row.id("id"),
                    start: row.timestamp("start_at"),
                    end: row.timestamp("end_at"),
                    mode: try row.enumValue("mode"),
                    weight: row["weight"]
                )
            }
        }
    }
}
