import Foundation
import GRDB
import TaktCore

/// An entry with all its segments, oldest first.
public struct EntryWithSegments: Hashable, Sendable, Identifiable {
    public var entry: TimeEntry
    public var segments: [Segment]

    public init(entry: TimeEntry, segments: [Segment]) {
        self.entry = entry
        self.segments = segments
    }

    public var id: EntryID { entry.id }

    public var openSegment: Segment? { segments.first(where: \.isOpen) }

    /// Tracked time, open segments counted up to `now`.
    public func duration(at now: Timestamp) -> TimeInterval {
        segments.reduce(0) { $0 + $1.duration(at: now) }
    }
}

/// What the timeline shows for a range.
public struct TimelineData: Hashable, Sendable {
    public var entries: [EntryWithSegments]
    /// Inactivity that was not kept as work time.
    public var idleEvents: [IdleEvent]

    public init(entries: [EntryWithSegments] = [], idleEvents: [IdleEvent] = []) {
        self.entries = entries
        self.idleEvents = idleEvents
    }
}

/// Read-only queries on entries and segments for the UI and analytics.
public struct EntryQueries: Sendable {
    let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    public func entry(_ id: EntryID) async throws -> TimeEntry? {
        try await database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM time_entry WHERE id = ?", arguments: [id.uuidString])
                .map(TimeEntry.init(row:))
        }
    }

    /// Non-deleted entries with a segment overlapping `range`, with all their segments, ordered by
    /// their first segment. Open segments count as running until `now`.
    public func timeline(in range: Range<Timestamp>, now: Timestamp) async throws -> TimelineData {
        try await database.writer.read { db in
            let arguments: StatementArguments = [
                "now": now.milliseconds,
                "rangeStart": range.lowerBound.milliseconds,
                "rangeEnd": range.upperBound.milliseconds,
            ]
            let entries = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM time_entry
                    WHERE deleted_at IS NULL AND id IN (
                      SELECT entry_id FROM segment
                      WHERE start_at < :rangeEnd AND COALESCE(end_at, :now) > :rangeStart
                    )
                    """,
                arguments: arguments
            ).map(TimeEntry.init(row:))
            guard !entries.isEmpty else {
                return TimelineData(idleEvents: try Self.idleEvents(db, arguments))
            }
            let ids = entries.map(\.id.uuidString)
            let segments = try Row.fetchAll(
                db,
                sql:
                    "SELECT * FROM segment WHERE entry_id IN (\(databaseQuestionMarks(count: ids.count))) ORDER BY start_at",
                arguments: StatementArguments(ids)
            ).map(Segment.init(row:))
            let byEntry = Dictionary(grouping: segments, by: \.entryID)
            let combined =
                entries
                .map { EntryWithSegments(entry: $0, segments: byEntry[$0.id] ?? []) }
                .sorted { ($0.segments.first?.start ?? now) < ($1.segments.first?.start ?? now) }
            return TimelineData(entries: combined, idleEvents: try Self.idleEvents(db, arguments))
        }
    }

    private static func idleEvents(_ db: Database, _ arguments: StatementArguments) throws -> [IdleEvent] {
        try Row.fetchAll(
            db,
            sql: """
                SELECT * FROM idle_event
                WHERE (resolution IS NULL OR resolution != 'kept')
                  AND start_at < :rangeEnd AND end_at > :rangeStart
                ORDER BY start_at
                """,
            arguments: arguments
        ).map(IdleEvent.init(row:))
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
