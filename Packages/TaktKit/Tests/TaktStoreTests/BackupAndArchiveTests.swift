import Foundation
import GRDB
import TaktCore
import Testing

@testable import TaktStore

// MARK: - DatabaseBackupTests

struct DatabaseBackupTests {

  // MARK: Internal

  @Test
  func keepsOneBackupPerDayAndFourteenGenerations() throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = try AppDatabase.inMemory()
    let backup = DatabaseBackup(directory: directory, timeZone: TimeZone(identifier: "Europe/Berlin") ?? .gmt)
    var now = Timestamp(milliseconds: 1_790_000_000_000)

    for _ in 0..<16 {
      #expect(try backup.backupIfNeeded(database, now: now) != nil)
      #expect(try backup.backupIfNeeded(database, now: now) == nil)
      now = now.adding(seconds: day)
    }

    let files = try backup.backups()
    #expect(files.count == 14)
    #expect(files.first?.lastPathComponent == "takt-2026-09-23.sqlite")
    #expect(files.last?.lastPathComponent == "takt-2026-10-06.sqlite")
  }

  @Test
  func backupContainsTheData() async throws {
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = try AppDatabase.inMemory()
    let clock = ManualClock()
    let id = try await TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
      .start(EntryDraft(title: "Backed up"), mode: .switchTo).value

    let url = try #require(try DatabaseBackup(directory: directory).backupIfNeeded(database, now: clock.now()))
    let restored = try AppDatabase(DatabaseQueue(path: url.path))
    #expect(try await GRDBTimerStore(database: restored).snapshot().entry(id)?.entry.title == "Backed up")
  }

  // MARK: Private

  private let directory = FileManager.default.temporaryDirectory.appending(path: "takt-backups-\(UUID().uuidString)")
  private let day: TimeInterval = 86_400

}

// MARK: - DatabaseArchiveTests

struct DatabaseArchiveTests {

  // MARK: Internal

  @Test
  func exportThenImportReproducesAllData() async throws {
    let source = try await filledDatabase()
    let data = try DatabaseArchive.export(source)

    let target = try AppDatabase.inMemory()
    try DatabaseArchive.importReplacingAll(data, into: target)

    #expect(try DatabaseArchive.export(target) == data)
    #expect(try await GRDBTimerStore(database: target).snapshot() == GRDBTimerStore(database: source).snapshot())
  }

  @Test
  func importReplacesExistingData() async throws {
    let target = try await filledDatabase()
    let empty = try DatabaseArchive.export(try AppDatabase.inMemory())

    try DatabaseArchive.importReplacingAll(empty, into: target)

    let count = try await target.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM time_entry") }
    #expect(count == 0)
  }

  @Test
  func archiveFromNewerSchemaIsRejectedWithoutChanges() async throws {
    let target = try await filledDatabase()
    let before = try DatabaseArchive.export(target)
    var archive = try JSONDecoder().decode(DatabaseArchive.Archive.self, from: before)
    archive.migrations.append("v99")
    archive.tables["time_entry"] = []

    #expect(throws: DatabaseArchive.ImportError.newerSchema(missingMigrations: ["v99"])) {
      try DatabaseArchive.importReplacingAll(try JSONEncoder().encode(archive), into: target)
    }
    #expect(try DatabaseArchive.export(target) == before)
  }

  @Test
  func brokenReferencesRollBackTheImport() async throws {
    let target = try await filledDatabase()
    let before = try DatabaseArchive.export(target)
    var archive = try JSONDecoder().decode(DatabaseArchive.Archive.self, from: before)
    archive.tables["time_entry"] = [] // segments now point nowhere

    #expect(throws: DatabaseError.self) {
      try DatabaseArchive.importReplacingAll(try JSONEncoder().encode(archive), into: target)
    }
    #expect(try DatabaseArchive.export(target) == before)
  }

  @Test
  func unknownColumnsAreRejected() throws {
    var archive = try JSONDecoder().decode(
      DatabaseArchive.Archive.self,
      from: try DatabaseArchive.export(try AppDatabase.inMemory()),
    )
    archive.tables["setting"] = [["key": .text("a"), "value": .text("b"), "evil); DROP TABLE x; --": .null]]

    #expect(throws: DatabaseArchive.ImportError.unknownColumn(table: "setting", column: "evil); DROP TABLE x; --")) {
      try DatabaseArchive.importReplacingAll(try JSONEncoder().encode(archive), into: try AppDatabase.inMemory())
    }
  }

  @Test
  func fileExportAndImportRoundTrip() async throws {
    let source = try await filledDatabase()
    let url = FileManager.default.temporaryDirectory.appending(path: "takt-archive-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: url) }

    try await DatabaseArchive.export(source, to: url)
    let target = try AppDatabase.inMemory()
    try await DatabaseArchive.importReplacingAll(contentsOf: url, into: target)

    #expect(try DatabaseArchive.export(target) == DatabaseArchive.export(source))
  }

  // MARK: Private

  private func filledDatabase() async throws -> AppDatabase {
    let database = try AppDatabase.inMemory()
    let clock = ManualClock()
    let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    let a = try await engine.start(EntryDraft(title: "Ä – Unicode & \"Quotes\"", weight: 0.3), mode: .switchTo)
      .value
    clock.advance(seconds: 90)
    _ = try await engine.start(EntryDraft(title: "B", note: "Notiz"), mode: .parallel)
    clock.advance(seconds: 30)
    try await engine.stop(a)
    _ = try await engine.pauseAll()
    try await engine.heartbeat()
    return database
  }

}
