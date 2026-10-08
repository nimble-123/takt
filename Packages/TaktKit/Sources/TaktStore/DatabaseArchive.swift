import Foundation
import GRDB

/// JSON export and import of all data (NFR Datensicherheit).
///
/// Every table is written as a list of rows with their raw column values, so new tables and
/// columns are covered without extra code. Import replaces all data in one transaction.
public enum DatabaseArchive {

  // MARK: Public

  public enum ImportError: Error, Equatable {
    case unknownFormat
    /// The archive was written by a newer schema than this app knows.
    case newerSchema(missingMigrations: [String])
    case unknownTable(String)
    case unknownColumn(table: String, column: String)
  }

  public static let format = "de.nilslutz.takt"

  public static func export(_ database: AppDatabase) throws -> Data {
    let archive = try database.writer.read { db in
      var tables = [String: [[String: Value]]]()
      for table in try dataTables(db) {
        tables[table] = try Row.fetchAll(db, sql: "SELECT * FROM \(table)").map { row in
          Dictionary(uniqueKeysWithValues: row.map { ($0, Value($1)) })
        }
      }
      return Archive(
        format: format,
        migrations: try AppDatabase.migrator.appliedMigrations(db),
        tables: tables,
      )
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(archive)
  }

  /// Replaces all data with the archive's content. Nothing changes if the import fails.
  public static func importReplacingAll(_ data: Data, into database: AppDatabase) throws {
    let archive = try JSONDecoder().decode(Archive.self, from: data)
    guard archive.format == format else { throw ImportError.unknownFormat }

    try database.writer.write { db in
      let known = try AppDatabase.migrator.appliedMigrations(db)
      let missing = archive.migrations.filter { !known.contains($0) }
      guard missing.isEmpty else { throw ImportError.newerSchema(missingMigrations: missing) }

      let tables = try dataTables(db)
      for table in archive.tables.keys where !tables.contains(table) {
        throw ImportError.unknownTable(table)
      }

      // Rows reference each other across tables; check foreign keys at commit.
      try db.execute(sql: "PRAGMA defer_foreign_keys = ON")
      for table in tables {
        try db.execute(sql: "DELETE FROM \(table)")
      }
      for (table, rows) in archive.tables {
        let columns = Set(try db.columns(in: table).map(\.name))
        for row in rows {
          let names = row.keys.sorted()
          if let unknown = names.first(where: { !columns.contains($0) }) {
            throw ImportError.unknownColumn(table: table, column: unknown)
          }
          let quoted = names.map { $0.quotedDatabaseIdentifier }.joined(separator: ", ")
          try db.execute(
            sql: "INSERT INTO \(table) (\(quoted)) VALUES (\(databaseQuestionMarks(count: names.count)))",
            arguments: StatementArguments(names.compactMap { row[$0]?.databaseValue }),
          )
        }
      }
    }
  }

  // MARK: Internal

  struct Archive: Codable {
    var format: String
    var migrations: [String]
    var tables: [String: [[String: Value]]]
  }

  enum Value: Codable, Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)

    // MARK: Lifecycle

    init(_ dbValue: DatabaseValue) {
      switch dbValue.storage {
      case .null, .blob: self = .null
      case .int64(let value): self = .integer(value)
      case .double(let value): self = .real(value)
      case .string(let value): self = .text(value)
      }
    }

    init(from decoder: any Decoder) throws {
      let container = try decoder.singleValueContainer()
      if container.decodeNil() {
        self = .null
      } else if let value = try? container.decode(Int64.self) {
        self = .integer(value)
      } else if let value = try? container.decode(Double.self) {
        self = .real(value)
      } else {
        self = .text(try container.decode(String.self))
      }
    }

    // MARK: Internal

    var databaseValue: DatabaseValue {
      switch self {
      case .null: .null
      case .integer(let value): value.databaseValue
      case .real(let value): value.databaseValue
      case .text(let value): value.databaseValue
      }
    }

    func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      switch self {
      case .null: try container.encodeNil()
      case .integer(let value): try container.encode(value)
      case .real(let value): try container.encode(value)
      case .text(let value): try container.encode(value)
      }
    }
  }

  // MARK: Private

  /// All tables that hold app data, i.e. not SQLite's or GRDB's own and not the full-text index,
  /// which its triggers rebuild while the rows are imported.
  private static func dataTables(_ db: Database) throws -> [String] {
    try String.fetchAll(
      db,
      sql: """
        SELECT name FROM sqlite_master
        WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name != 'grdb_migrations'
          AND name NOT LIKE 'search_index%'
        ORDER BY name
        """,
    )
  }
}
