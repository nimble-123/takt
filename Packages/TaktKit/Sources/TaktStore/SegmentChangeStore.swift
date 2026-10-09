import GRDB
import TaktCore

// MARK: - SegmentChangeStore

/// Reads the change log (AZ-04). The timer store writes it, in the transaction of the change.
public struct SegmentChangeStore: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

  /// The records of an entry's segments, oldest first.
  public func records(ofEntry id: EntryID) async throws -> [SegmentChangeRecord] {
    try await database.writer.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT * FROM segment_change WHERE entry_id = ? ORDER BY changed_at, rowid",
        arguments: [id.uuidString],
      ).map(SegmentChangeRecord.init(row:))
    }
  }

  /// All records made in `range`, oldest first, e.g. for the appendix of the time record.
  public func records(changedIn range: Range<Timestamp>) async throws -> [SegmentChangeRecord] {
    try await database.writer.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT * FROM segment_change WHERE changed_at >= ? AND changed_at < ? ORDER BY changed_at, rowid",
        arguments: [range.lowerBound.milliseconds, range.upperBound.milliseconds],
      ).map(SegmentChangeRecord.init(row:))
    }
  }

  // MARK: Private

  private let database: AppDatabase

}

// MARK: - SegmentChangeRecord + TableRow

extension SegmentChangeRecord: TableRow {

  // MARK: Lifecycle

  init(row: Row) throws {
    self.init(
      id: try row.id("id"),
      segmentID: try row.id("segment_id"),
      entryID: try row.id("entry_id"),
      kind: try row.enumValue("kind"),
      oldStart: row.optionalTimestamp("old_start_at"),
      oldEnd: row.optionalTimestamp("old_end_at"),
      newStart: row.optionalTimestamp("new_start_at"),
      newEnd: row.optionalTimestamp("new_end_at"),
      changedAt: row.timestamp("changed_at"),
      reason: row["reason"],
    )
  }

  // MARK: Internal

  static let table = "segment_change"

  var rowID: String {
    id.uuidString
  }

  var columns: [String: (any DatabaseValueConvertible)?] {
    [
      "id": id.uuidString,
      "segment_id": segmentID.uuidString,
      "entry_id": entryID.uuidString,
      "kind": kind.rawValue,
      "old_start_at": oldStart?.milliseconds,
      "old_end_at": oldEnd?.milliseconds,
      "new_start_at": newStart?.milliseconds,
      "new_end_at": newEnd?.milliseconds,
      "changed_at": changedAt.milliseconds,
      "reason": reason,
    ]
  }
}
