import Foundation
import GRDB
import TaktCore

// MARK: - OvertimePayoutStore

/// Overtime payouts (AZ-07) as raw data. Removing one marks it with the time instead of deleting
/// it, so a correction stays traceable.
public struct OvertimePayoutStore: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

  /// Payouts not removed from `first` through `last`, both `YYYY-MM-DD`, by day.
  public func payouts(from first: String, through last: String) async throws -> [OvertimePayout] {
    try await database.writer.read { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT * FROM overtime_payout
          WHERE deleted_at IS NULL AND day >= ? AND day <= ?
          ORDER BY day, created_at
          """,
        arguments: [first, last],
      ).map(OvertimePayout.init(row:))
    }
  }

  public func add(_ payout: OvertimePayout) async throws {
    try await database.writer.write { db in
      try db.execute(
        sql: "INSERT INTO overtime_payout (id, day, seconds, note, created_at) VALUES (?, ?, ?, ?, ?)",
        arguments: [
          payout.id.uuidString,
          payout.day,
          Int64(payout.seconds.rounded()),
          payout.note,
          payout.createdAt.milliseconds,
        ],
      )
    }
  }

  /// Marks a payout as removed at `time`.
  public func remove(_ id: OvertimePayoutID, at time: Timestamp) async throws {
    try await database.writer.write { db in
      try db.execute(
        sql: "UPDATE overtime_payout SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL",
        arguments: [time.milliseconds, id.uuidString],
      )
    }
  }

  // MARK: Private

  private let database: AppDatabase

}

// MARK: - OvertimePayout + Row

extension OvertimePayout {
  fileprivate init(row: Row) throws {
    self.init(
      id: try row.id("id"),
      day: row["day"],
      seconds: TimeInterval(row["seconds"] as Int64),
      note: row["note"],
      createdAt: row.timestamp("created_at"),
    )
  }
}
