import GRDB
import TaktCore

// MARK: - SeriesRuleStore

/// Assignments per Outlook series (CA-20). A handful of rows, so callers load them all.
public struct SeriesRuleStore: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

  public func all() async throws -> [SeriesRule] {
    try await database.writer.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM series_rule ORDER BY series_id").map(SeriesRule.init(row:))
    }
  }

  /// Stores `rule`; an empty rule removes the row.
  public func save(_ rule: SeriesRule, at now: Timestamp) async throws {
    try await database.writer.write { db in
      if rule.isEmpty {
        try db.execute(sql: "DELETE FROM series_rule WHERE series_id = ?", arguments: [rule.seriesID])
        return
      }
      try db.execute(
        sql: """
          INSERT OR REPLACE INTO series_rule
            (series_id, project_id, category_id, work_item_link_id, offers_timer_at_start, ends_with_event, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          rule.seriesID,
          rule.projectID?.uuidString,
          rule.categoryID?.uuidString,
          rule.workItemLinkID?.uuidString,
          rule.offersTimerAtStart,
          rule.endsWithEvent,
          now.milliseconds,
        ],
      )
    }
  }

  // MARK: Private

  private let database: AppDatabase
}

// MARK: - SeriesRule + Row

extension SeriesRule {
  init(row: Row) throws {
    self.init(
      seriesID: row["series_id"],
      projectID: try row.optionalID("project_id"),
      categoryID: try row.optionalID("category_id"),
      workItemLinkID: try row.optionalID("work_item_link_id"),
      offersTimerAtStart: row["offers_timer_at_start"],
      endsWithEvent: row["ends_with_event"],
    )
  }
}
