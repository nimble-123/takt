import Foundation
import GRDB

/// The app's SQLite database with all migrations applied.
public struct AppDatabase: Sendable {

  // MARK: Lifecycle

  /// Wraps `writer` and migrates it to the current schema.
  public init(_ writer: any DatabaseWriter) throws {
    self.writer = writer
    try Self.migrator.migrate(writer)
  }

  // MARK: Public

  public let writer: any DatabaseWriter

  /// Opens (or creates) the database file in WAL mode.
  public static func open(at url: URL) throws -> AppDatabase {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )
    return try AppDatabase(DatabasePool(path: url.path))
  }

  /// An empty in-memory database for tests and previews.
  public static func inMemory() throws -> AppDatabase {
    try AppDatabase(DatabaseQueue())
  }

  /// `~/Library/Application Support/Takt/takt.sqlite`
  public static func defaultURL() throws -> URL {
    try FileManager.default
      .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appending(components: "Takt", "takt.sqlite")
  }

  // MARK: Internal

  /// Migrations are append-only: never change an existing one, add a new one instead.
  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1", migrate: Schema.v1)
    migrator.registerMigration("v2-work-item-details", migrate: Schema.v2)
    migrator.registerMigration("v3-search", migrate: Schema.v3)
    migrator.registerMigration("v4-segment-indexes", migrate: Schema.v4)
    return migrator
  }
}
