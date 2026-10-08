import Foundation
import GRDB
import TaktCore

// MARK: - TableRow

/// Maps a TaktCore model to one row of a table. IDs are written as `uuidString`, times as UTC milliseconds.
protocol TableRow: Equatable, Sendable {
  init(row: Row) throws

  static var table: String { get }

  var rowID: String { get }
  var columns: [String: (any DatabaseValueConvertible)?] { get }
}

// MARK: - RowDecodingError

enum RowDecodingError: Error {
  case invalidValue(column: String)
}

extension Row {
  func id<ID: UUIDIdentifier>(_ column: String) throws -> ID {
    guard let id = ID(uuidString: self[column]) else { throw RowDecodingError.invalidValue(column: column) }
    return id
  }

  func optionalID<ID: UUIDIdentifier>(_ column: String) throws -> ID? {
    guard let string: String = self[column] else { return nil }
    guard let id = ID(uuidString: string) else { throw RowDecodingError.invalidValue(column: column) }
    return id
  }

  func timestamp(_ column: String) -> Timestamp {
    Timestamp(milliseconds: self[column])
  }

  func optionalTimestamp(_ column: String) -> Timestamp? {
    (self[column] as Int64?).map(Timestamp.init(milliseconds:))
  }

  func enumValue<Value: RawRepresentable>(_ column: String) throws -> Value where Value.RawValue == String {
    guard let value = Value(rawValue: self[column]) else { throw RowDecodingError.invalidValue(column: column) }
    return value
  }

  func optionalEnumValue<Value: RawRepresentable>(_ column: String) throws -> Value?
    where Value.RawValue == String
  {
    guard let raw: String = self[column] else { return nil }
    guard let value = Value(rawValue: raw) else { throw RowDecodingError.invalidValue(column: column) }
    return value
  }

  func entryIDs(_ column: String) throws -> [EntryID] {
    let strings = try JSONDecoder().decode([String].self, from: Data((self[column] as String).utf8))
    return try strings.map { string in
      guard let id = EntryID(uuidString: string) else { throw RowDecodingError.invalidValue(column: column) }
      return id
    }
  }
}

func entryIDsJSON(_ ids: [EntryID]) -> String {
  let data = (try? JSONEncoder().encode(ids.map(\.uuidString))) ?? Data("[]".utf8)
  return String(decoding: data, as: UTF8.self)
}

// MARK: - TimeEntry + TableRow

extension TimeEntry: TableRow {

  // MARK: Lifecycle

  init(row: Row) throws {
    self.init(
      id: try row.id("id"),
      title: row["title"],
      projectID: try row.optionalID("project_id"),
      taskID: try row.optionalID("task_id"),
      categoryID: try row.optionalID("category_id"),
      workItemLinkID: try row.optionalID("work_item_link_id"),
      note: row["note"],
      countingMode: try row.optionalEnumValue("counting_mode"),
      weight: row["weight"],
      state: try row.enumValue("state"),
      createdAt: row.timestamp("created_at"),
      updatedAt: row.timestamp("updated_at"),
      deletedAt: row.optionalTimestamp("deleted_at"),
    )
  }

  // MARK: Internal

  static let table = "time_entry"

  var rowID: String {
    id.uuidString
  }

  var columns: [String: (any DatabaseValueConvertible)?] {
    [
      "id": id.uuidString,
      "title": title,
      "project_id": projectID?.uuidString,
      "task_id": taskID?.uuidString,
      "category_id": categoryID?.uuidString,
      "work_item_link_id": workItemLinkID?.uuidString,
      "note": note,
      "counting_mode": countingMode?.rawValue,
      "weight": weight,
      "state": state.rawValue,
      "created_at": createdAt.milliseconds,
      "updated_at": updatedAt.milliseconds,
      "deleted_at": deletedAt?.milliseconds,
    ]
  }
}

// MARK: - Segment + TableRow

extension Segment: TableRow {

  // MARK: Lifecycle

  init(row: Row) throws {
    self.init(
      id: try row.id("id"),
      entryID: try row.id("entry_id"),
      start: row.timestamp("start_at"),
      end: row.optionalTimestamp("end_at"),
      source: try row.enumValue("source"),
    )
  }

  // MARK: Internal

  static let table = "segment"

  var rowID: String {
    id.uuidString
  }

  var columns: [String: (any DatabaseValueConvertible)?] {
    [
      "id": id.uuidString,
      "entry_id": entryID.uuidString,
      "start_at": start.milliseconds,
      "end_at": end?.milliseconds,
      "source": source.rawValue,
    ]
  }
}

// MARK: - GlobalPause + TableRow

extension GlobalPause: TableRow {

  // MARK: Lifecycle

  init(row: Row) throws {
    self.init(
      id: try row.id("id"),
      pausedAt: row.timestamp("paused_at"),
      entryIDs: try row.entryIDs("entry_ids"),
      resumedAt: row.optionalTimestamp("resumed_at"),
    )
  }

  // MARK: Internal

  static let table = "global_pause"

  var rowID: String {
    id.uuidString
  }

  var columns: [String: (any DatabaseValueConvertible)?] {
    [
      "id": id.uuidString,
      "paused_at": pausedAt.milliseconds,
      "entry_ids": entryIDsJSON(entryIDs),
      "resumed_at": resumedAt?.milliseconds,
    ]
  }
}

// MARK: - IdleEvent + TableRow

extension IdleEvent: TableRow {

  // MARK: Lifecycle

  init(row: Row) throws {
    self.init(
      id: try row.id("id"),
      start: row.timestamp("start_at"),
      end: row.timestamp("end_at"),
      entryIDs: try row.entryIDs("entry_ids"),
      resolution: try row.optionalEnumValue("resolution"),
      targetEntryID: try row.optionalID("entry_id"),
    )
  }

  // MARK: Internal

  static let table = "idle_event"

  var rowID: String {
    id.uuidString
  }

  var columns: [String: (any DatabaseValueConvertible)?] {
    [
      "id": id.uuidString,
      "start_at": start.milliseconds,
      "end_at": end.milliseconds,
      "entry_ids": entryIDsJSON(entryIDs),
      "resolution": resolution?.rawValue,
      "entry_id": targetEntryID?.uuidString,
    ]
  }
}
