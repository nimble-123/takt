import Foundation
import GRDB
import TaktCore

/// Rules as one JSON value in `setting`; their order is their priority (ST-05).
/// Backups and the JSON archive include them without a table of their own.
public struct RuleStore: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

  public func load() async throws -> [Rule] {
    try await database.writer.read { db in
      guard
        let json = try String.fetchOne(
          db,
          sql: "SELECT value FROM setting WHERE key = ?",
          arguments: [Self.key],
        )
      else { return [] }
      return try JSONDecoder().decode([Rule].self, from: Data(json.utf8))
    }
  }

  public func save(_ rules: [Rule]) async throws {
    let json = String(decoding: try JSONEncoder().encode(rules), as: UTF8.self)
    try await database.writer.write { db in
      try db.execute(
        sql: "INSERT OR REPLACE INTO setting (key, value) VALUES (?, ?)",
        arguments: [Self.key, json],
      )
    }
  }

  // MARK: Internal

  static let key = "rules"

  // MARK: Private

  private let database: AppDatabase

}
