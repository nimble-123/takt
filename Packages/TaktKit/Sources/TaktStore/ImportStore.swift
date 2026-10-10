import GRDB
import TaktCore

/// Writes data taken over from another record, e.g. the Excel timesheet (#190), in one
/// transaction. Unlike edits it adds nothing to the change log (AZ-04), and it never replaces
/// what Takt already holds: existing absences stay, entries are only ever added.
public struct ImportStore: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    self.database = database
  }

  // MARK: Public

  /// Adds the entries with their segments and the absences of days without one.
  public func add(_ entries: [EntryWithSegments], absences: [String: AbsenceKind]) async throws {
    try await database.writer.write { db in
      for entry in entries {
        try entry.entry.insertRow(into: db)
        for segment in entry.segments {
          try segment.insertRow(into: db)
        }
      }
      for (day, kind) in absences {
        try db.execute(sql: "INSERT OR IGNORE INTO absence (day, kind) VALUES (?, ?)", arguments: [day, kind.rawValue])
      }
    }
  }

  /// Deletes the entries that have imported segments, with their segments and tags. Returns how
  /// many. Imported entries are never linked to a work item, so no booking refers to them.
  @discardableResult
  public func removeImported() async throws -> Int {
    try await database.writer.write { db in
      try db.execute(
        sql: "DELETE FROM time_entry WHERE id IN (SELECT DISTINCT entry_id FROM segment WHERE source = 'import')"
      )
      return db.changesCount
    }
  }

  // MARK: Private

  private let database: AppDatabase
}
