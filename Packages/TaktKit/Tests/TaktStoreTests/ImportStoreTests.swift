import GRDB
import TaktCore
import Testing

@testable import TaktStore

/// Data taken over from the Excel timesheet (#190).
struct ImportStoreTests {

  @Test
  func migrationKeepsSegmentsAndAllowsTheImportSource() throws {
    let queue = try DatabaseQueue()
    try AppDatabase.migrator.migrate(queue, upTo: "v9-overtime-payout")
    let entry = TimeEntry(draft: EntryDraft(title: "Alt"), state: .stopped, at: Timestamp(milliseconds: 0))
    let segment = Segment(
      entryID: entry.id,
      start: Timestamp(milliseconds: 0),
      end: Timestamp(milliseconds: 60_000),
      source: .live,
    )
    try queue.write { db in
      try entry.insertRow(into: db)
      try segment.insertRow(into: db)
    }

    let database = try AppDatabase(queue)

    try queue.read { db in
      #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM segment WHERE source = 'live'") == 1)
      let indexes = try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'segment' ORDER BY name",
      )
      #expect(indexes.contains("segment_open"))
      #expect(indexes.contains("segment_entry"))
      #expect(indexes.contains("segment_time"))
    }
    _ = database
  }

  @Test
  func importAddsEntriesWithoutChangeLogAndKeepsExistingAbsences() async throws {
    let database = try AppDatabase.inMemory()
    try await AbsenceStore(database: database).set(.sick, on: "2026-01-05")
    let entry = TimeEntry(draft: EntryDraft(title: "Arbeitszeit"), state: .stopped, at: Timestamp(milliseconds: 0))
    let segments = [
      Segment(entryID: entry.id, start: Timestamp(milliseconds: 0), end: Timestamp(milliseconds: 3_600_000), source: .imported),
      Segment(
        entryID: entry.id,
        start: Timestamp(milliseconds: 5_400_000),
        end: Timestamp(milliseconds: 9_000_000),
        source: .imported,
      ),
    ]

    try await ImportStore(database: database)
      .add([EntryWithSegments(entry: entry, segments: segments)], absences: ["2026-01-05": .vacation, "2026-01-06": .vacation])

    let stored = try await EntryQueries(database: database).entries([entry.id])
    #expect(stored.first?.segments.map(\.source) == [.imported, .imported])
    let changes = try await database.writer.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM segment_change") }
    #expect(changes == 0)
    let absences = try await AbsenceStore(database: database).absences(from: "2026-01-01", through: "2026-01-31")
    #expect(absences == ["2026-01-05": .sick, "2026-01-06": .vacation])
  }
}
