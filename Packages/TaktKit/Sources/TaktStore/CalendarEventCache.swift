import Foundation
import GRDB
import TaktCore

// MARK: - CalendarEventCache

/// Outlook events of today ± 7 days, so the start search works offline and instantly (CA-05).
public struct CalendarEventCache: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

  /// Replaces the cache with those of `events` that overlap `start..<end`, so it never grows
  /// beyond one sync window and cancelled or declined events disappear.
  public func replace(_ events: [CalendarEvent], from start: Timestamp, to end: Timestamp) async throws {
    try await database.writer.write { db in
      try db.execute(sql: "DELETE FROM calendar_event")
      for event in events where event.end > start && event.start < end {
        try db.execute(
          sql: """
            INSERT OR REPLACE INTO calendar_event
              (id, series_id, title, start_at, end_at, attendee_count, is_online_meeting, is_private)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
          arguments: [
            event.id,
            event.seriesID,
            event.isPrivate ? "" : event.title,
            event.start.milliseconds,
            event.end.milliseconds,
            event.attendeeCount,
            event.isOnlineMeeting,
            event.isPrivate,
          ],
        )
      }
    }
  }

  /// Events overlapping `start..<end`, earliest first.
  public func events(from start: Timestamp, to end: Timestamp) async throws -> [CalendarEvent] {
    try await database.writer.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT * FROM calendar_event WHERE end_at > ? AND start_at < ? ORDER BY start_at, id",
        arguments: [start.milliseconds, end.milliseconds],
      ).map(CalendarEvent.init(row:))
    }
  }

  /// Events not yet over at `now` whose title contains `text` (all of them for empty text),
  /// earliest first (CA-10, CA-11).
  public func search(_ text: String, at now: Timestamp, limit: Int = 8) async throws -> [CalendarEvent] {
    try await database.writer.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT * FROM calendar_event
          WHERE end_at > :now AND (:text = '' OR (is_private = 0 AND title LIKE :pattern ESCAPE '\\'))
          ORDER BY start_at, id
          LIMIT :limit
          """,
        arguments: [
          "now": now.milliseconds,
          "text": text,
          "limit": limit,
          "pattern": "%"
            + text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%",
        ],
      ).map(CalendarEvent.init(row:))
    }
  }

  // MARK: Private

  private let database: AppDatabase
}

// MARK: - CalendarEvent + Row

extension CalendarEvent {
  init(row: Row) {
    self.init(
      id: row["id"],
      seriesID: row["series_id"],
      title: row["title"],
      start: row.timestamp("start_at"),
      end: row.timestamp("end_at"),
      attendeeCount: row["attendee_count"],
      isOnlineMeeting: row["is_online_meeting"],
      isPrivate: row["is_private"],
    )
  }
}
