import GRDB
import TaktCore
import Testing

@testable import TaktStore

struct SearchIndexTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    search = SearchIndex(database: database)
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
  }

  // MARK: Internal

  @Test
  func findsEntriesByTitleAndNoteIgnoringCaseAndUmlauts() async throws {
    let review = try await entry("Code-Review Login", note: "Größere Änderung am Interceptor")
    try await entry("Daily Standup")

    #expect(try await search.search("login").map(\.ref) == [review.uuidString])
    // Umlauts fold to their base letter; ß stays ß (FTS5 unicode61).
    let hit = try #require(try await search.search("anderung").first)
    #expect(hit.ref == review.uuidString)
    #expect(hit.snippet?.contains("**Änderung**") == true)
    #expect(try await search.search("größ").map(\.ref) == [review.uuidString])
  }

  @Test
  func wordsAreCombinedAsPrefixes() async throws {
    try await entry("Token-Refresh im Interceptor")
    try await entry("Token für Graph")
    #expect(try await search.search("tok inter").count == 1)
    #expect(try await search.search("tok").count == 2)
  }

  @Test
  func titleHitsRankAboveNoteHits() async throws {
    let inNote = try await entry("Planung", note: "Login besprechen")
    let inTitle = try await entry("Login-Seite")
    #expect(try await search.search("login").map(\.ref) == [inTitle.uuidString, inNote.uuidString])
  }

  @Test
  func indexFollowsChangesAndDeletions() async throws {
    let id = try await entry("Alt")
    let stored = try #require(try await EntryQueries(database: database).entry(id))
    try await engine.apply(EntryEdits.update(stored, now: clock.now()) { $0.title = "Neu" })
    #expect(try await search.search("alt").isEmpty)
    #expect(try await search.search("neu").count == 1)

    let renamed = try #require(try await EntryQueries(database: database).entry(id))
    try await engine.apply(EntryEdits.delete(renamed, openSegment: nil, now: clock.now()))
    #expect(try await search.search("neu").isEmpty)
  }

  @Test
  func catalogAndWorkItemsAreIndexed() async throws {
    let catalog = CatalogStore(database: database)
    let project = Project(name: "Kundenportal", color: "#2563EB", createdAt: clock.now())
    try await catalog.save(project)
    try await catalog.save(ProjectTask(projectID: project.id, name: "Login-Maske"))
    _ = try await catalog.tag(named: "dringend")
    try await WorkItemCache(database: database).store([
      WorkItemLink(
        organization: "o",
        project: "p",
        workItemID: 1234,
        cachedTitle: "SSO",
        descriptionExcerpt: "Kundenportal Anmeldung",
      )
    ])

    #expect(Set(try await search.search("kundenportal").map(\.kind)) == [.project, .workItem])
    #expect(try await search.search("login").map(\.kind) == [.task])
    #expect(try await search.search("dringend").map(\.kind) == [.tag])
    #expect(try await search.search("#1234").map(\.kind) == [.workItem])
  }

  @Test
  func userInputNeverBecomesQuerySyntax() async throws {
    try await entry("A AND B")
    #expect(try await search.search("\"unbalanced OR NOT (").isEmpty)
    #expect(try await search.search("  ").isEmpty)
    #expect(SearchIndex.matchQuery("a-b \"c\"") == #""a"* "b"* "c"*"#)
  }

  @Test
  func existingRowsAreIndexedByTheMigration() throws {
    let queue = try DatabaseQueue()
    var migrator = AppDatabase.migrator
    try migrator.migrate(queue, upTo: "v2-work-item-details")
    try queue.write { db in
      try db.execute(
        sql: "INSERT INTO time_entry (id, title, created_at, updated_at) VALUES ('e', 'Vorhanden', 0, 0)"
      )
    }
    migrator = AppDatabase.migrator
    try migrator.migrate(queue)
    let count = try queue.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM search_index WHERE search_index MATCH '\"vorhanden\"*'")
    }
    #expect(count == 1)
  }

  @Test
  func archiveImportRebuildsTheIndex() async throws {
    try await entry("Exportiert")
    let data = try DatabaseArchive.export(database)
    let target = try AppDatabase.inMemory()
    try DatabaseArchive.importReplacingAll(data, into: target)
    #expect(try await SearchIndex(database: target).search("exportiert").count == 1)
  }

  // MARK: Private

  private let clock = ManualClock()
  private let database: AppDatabase
  private let search: SearchIndex
  private let engine: TimerEngine

  @discardableResult
  private func entry(_ title: String, note: String? = nil) async throws -> EntryID {
    try await engine.start(EntryDraft(title: title, note: note), mode: .parallel).value
  }

}
