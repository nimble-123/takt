import GRDB
import TaktCore

/// Absences per local day (AZ-05), stored as raw data: the day as `YYYY-MM-DD` and the kind.
public struct AbsenceStore: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

  /// Absences from `first` through `last`, both `YYYY-MM-DD`.
  public func absences(from first: String, through last: String) async throws -> [String: AbsenceKind] {
    try await database.writer.read { db in
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT day, kind FROM absence WHERE day >= ? AND day <= ?",
        arguments: [first, last],
      )
      return try Dictionary(uniqueKeysWithValues: rows.map { row in (row["day"] as String, try row.enumValue("kind")) })
    }
  }

  /// Sets or, with `nil`, removes the absence of a day.
  public func set(_ kind: AbsenceKind?, on day: String) async throws {
    try await database.writer.write { db in
      if let kind {
        try db.execute(
          sql: "INSERT OR REPLACE INTO absence (day, kind) VALUES (?, ?)",
          arguments: [day, kind.rawValue],
        )
      } else {
        try db.execute(sql: "DELETE FROM absence WHERE day = ?", arguments: [day])
      }
    }
  }

  // MARK: Private

  private let database: AppDatabase

}
