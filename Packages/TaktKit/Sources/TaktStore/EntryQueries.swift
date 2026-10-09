import Foundation
import GRDB
import TaktCore

// MARK: - EntryWithSegments

/// An entry with all its segments, oldest first.
public struct EntryWithSegments: Hashable, Sendable, Identifiable {

  // MARK: Lifecycle

  public init(entry: TimeEntry, segments: [Segment]) {
    self.entry = entry
    self.segments = segments
  }

  // MARK: Public

  public var entry: TimeEntry
  public var segments: [Segment]

  public var id: EntryID {
    entry.id
  }

  public var openSegment: Segment? {
    segments.first(where: \.isOpen)
  }

  /// Tracked time, open segments counted up to `now`.
  public func duration(at now: Timestamp) -> TimeInterval {
    segments.reduce(0) { $0 + $1.duration(at: now) }
  }
}

// MARK: - TimelineData

/// What the timeline shows for a range.
public struct TimelineData: Hashable, Sendable {
  public init(entries: [EntryWithSegments] = [], idleEvents: [IdleEvent] = []) {
    self.entries = entries
    self.idleEvents = idleEvents
  }

  public var entries: [EntryWithSegments]
  /// Inactivity that was not kept as work time.
  public var idleEvents: [IdleEvent]

}

// MARK: - EntryQueries

/// Read-only queries on entries and segments for the UI and analytics.
public struct EntryQueries: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

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
        arguments: arguments,
      ).map(TimeEntry.init(row:))
      guard !entries.isEmpty else {
        return TimelineData(idleEvents: try Self.idleEvents(db, arguments))
      }
      let ids = entries.map(\.id.uuidString)
      let segments = try Row.fetchAll(
        db,
        sql:
        "SELECT * FROM segment WHERE entry_id IN (\(databaseQuestionMarks(count: ids.count))) ORDER BY start_at",
        arguments: StatementArguments(ids),
      ).map(Segment.init(row:))
      let byEntry = Dictionary(grouping: segments, by: \.entryID)
      let combined =
        entries
          .map { EntryWithSegments(entry: $0, segments: byEntry[$0.id] ?? []) }
          .sorted { ($0.segments.first?.start ?? now) < ($1.segments.first?.start ?? now) }
      return TimelineData(entries: combined, idleEvents: try Self.idleEvents(db, arguments))
    }
  }

  /// Non-deleted entries with all their segments, in the order of `ids`; unknown IDs are skipped.
  public func entries(_ ids: [EntryID]) async throws -> [EntryWithSegments] {
    guard !ids.isEmpty else { return [] }
    return try await database.writer.read { db in
      let strings = ids.map(\.uuidString)
      let marks = databaseQuestionMarks(count: strings.count)
      let entries = try Row.fetchAll(
        db,
        sql: "SELECT * FROM time_entry WHERE deleted_at IS NULL AND id IN (\(marks))",
        arguments: StatementArguments(strings),
      ).map(TimeEntry.init(row:))
      let segments = try Row.fetchAll(
        db,
        sql: "SELECT * FROM segment WHERE entry_id IN (\(marks)) ORDER BY start_at",
        arguments: StatementArguments(strings),
      ).map(Segment.init(row:))
      let byEntry = Dictionary(grouping: segments, by: \.entryID)
      let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
      return ids.compactMap { id in
        byID[id].map { EntryWithSegments(entry: $0, segments: byEntry[id] ?? []) }
      }
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
        arguments: [limit],
      ).map { row in
        EntryDraft(
          title: row["title"],
          projectID: try row.optionalID("project_id"),
          taskID: try row.optionalID("task_id"),
          categoryID: try row.optionalID("category_id"),
          workItemLinkID: try row.optionalID("work_item_link_id"),
        )
      }
    }
  }

  /// Segments of non-deleted entries overlapping `range`, with the entries' effective counting
  /// settings. Open segments end at `now`. Feed the result to `Allocation.allocate(_:in:)`.
  public func allocationInputs(
    in range: Range<Timestamp>,
    now: Timestamp,
    defaultMode: CountingMode,
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
        ],
      ).map { row in
        Allocation.Input(
          entryID: try row.id("id"),
          start: row.timestamp("start_at"),
          end: row.timestamp("end_at"),
          mode: try row.enumValue("mode"),
          weight: row["weight"],
        )
      }
    }
  }

  /// All linked work items by ID; the table holds one row per work item.
  /// Start of the earliest segment of an entry that is not deleted; `nil` without any.
  public func firstSegmentStart() async throws -> Timestamp? {
    try await database.writer.read { db in
      try Int64.fetchOne(
        db,
        sql: """
          SELECT MIN(s.start_at) FROM segment s
          JOIN time_entry e ON e.id = s.entry_id
          WHERE e.deleted_at IS NULL
          """,
      ).map(Timestamp.init(milliseconds:))
    }
  }

  public func workItemLinks() async throws -> [WorkItemLinkID: WorkItemLink] {
    try await database.writer.read { db in
      let links = try Row.fetchAll(db, sql: "SELECT * FROM work_item_link").map(WorkItemLink.init(row:))
      return Dictionary(uniqueKeysWithValues: links.map { ($0.id, $0) })
    }
  }

  // MARK: Private

  private let database: AppDatabase

  private static func idleEvents(_ db: Database, _ arguments: StatementArguments) throws -> [IdleEvent] {
    try Row.fetchAll(
      db,
      sql: """
        SELECT * FROM idle_event
        WHERE (resolution IS NULL OR resolution != 'kept')
          AND start_at < :rangeEnd AND end_at > :rangeStart
        ORDER BY start_at
        """,
      arguments: arguments,
    ).map(IdleEvent.init(row:))
  }

}
