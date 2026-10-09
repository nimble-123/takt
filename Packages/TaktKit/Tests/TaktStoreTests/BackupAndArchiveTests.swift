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
  func importKeepsBookingsMadeAfterTheExport() async throws {
    let target = try await filledDatabase()
    let (entry, link) = try await linkedEntry(in: target)
    let records = SyncRecordStore(database: target)
    let sentBefore = booking(entry, link, status: .pending)
    try await records.insert(sentBefore)
    let archive = try DatabaseArchive.export(target)
    // After the export: the pending booking arrived, and another one was sent.
    var arrived = sentBefore
    arrived.status = .synced
    arrived.adoRevision = 58
    try await records.update(arrived)
    let sentAfter = booking(entry, link, status: .synced)
    try await records.insert(sentAfter)

    try DatabaseArchive.importReplacingAll(archive, into: target)

    // Azure DevOps has both bookings; without them the time would be booked a second time.
    #expect(try await records.record(sentBefore.id)?.status == .synced)
    #expect(try await records.record(sentAfter.id) == sentAfter)
  }

  @Test
  func importReportsBookingsWhoseEntryIsNotInTheArchive() async throws {
    let target = try await filledDatabase()
    let archive = try DatabaseArchive.export(target)
    let (entry, link) = try await linkedEntry(in: target)
    let records = SyncRecordStore(database: target)
    try await records.insert(booking(entry, link, status: .synced))

    let summary = try DatabaseArchive.importReplacingAll(archive, into: target)

    #expect(summary.droppedBookings == 1)
    #expect(try await records.pending().isEmpty)
    #expect(try await records.records(for: [entry]).isEmpty)
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

  /// An entry linked to a cached work item.
  private func linkedEntry(in database: AppDatabase) async throws -> (EntryID, WorkItemLinkID) {
    let links = try await WorkItemCache(database: database).store([
      WorkItemLink(organization: "contoso", project: "Kundenportal", workItemID: 1234, cachedTitle: "Token")
    ])
    let link = try #require(links.first).id
    let (entry, changes) = try EntryEdits.create(
      EntryDraft(title: "Refresh", workItemLinkID: link),
      from: Timestamp(milliseconds: 1_000_000),
      to: Timestamp(milliseconds: 1_000_000 + 1_800_000),
      now: Timestamp(milliseconds: 3_000_000),
    )
    try await TimerEngine(store: GRDBTimerStore(database: database), clock: ManualClock()).apply(changes)
    return (entry.id, link)
  }

  private func booking(_ entry: EntryID, _ link: WorkItemLinkID, status: SyncRecord.Status) -> SyncRecord {
    SyncRecord(
      entryID: entry,
      workItemLinkID: link,
      localDay: "1970-01-01",
      field: "Microsoft.VSTS.Scheduling.CompletedWork",
      deltaSeconds: 1800,
      status: status,
      adoRevision: status == .synced ? 58 : nil,
      createdAt: Timestamp(milliseconds: 3_000_000),
    )
  }

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
