import TaktCore
import Testing

@testable import TaktStore

struct CatalogStoreTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    catalog = CatalogStore(database: database)
  }

  // MARK: Internal

  @Test
  func projectsAndTasksAreSavedAndUpdated() async throws {
    var project = Project(name: "Kundenportal", color: "#2563EB", icon: "globe", createdAt: now)
    try await catalog.save(project)
    let task = ProjectTask(projectID: project.id, name: "Login")
    try await catalog.save(task)

    project.name = "Kundenportal 2"
    project.archived = true
    try await catalog.save(project)

    let loaded = try await catalog.load()
    #expect(loaded.projects == [project])
    #expect(loaded.tasks(of: project.id) == [task])
  }

  @Test
  func categoriesCountAsWorkUnlessMarkedOtherwise() async throws {
    var errand = EntryCategory(name: "Private", color: "#888888")
    try await catalog.save(errand)
    #expect(try await catalog.load().categories.first?.countsAsWork == true)

    errand.countsAsWork = false
    try await catalog.save(errand)
    #expect(try await catalog.load().categories == [errand])
  }

  @Test
  func emptyNamesAreRejected() async throws {
    await #expect(throws: CatalogStore.CatalogError.emptyName) {
      try await catalog.save(EntryCategory(name: "  ", color: "#000000"))
    }
  }

  @Test
  func taskNeedsItsProject() async throws {
    await #expect(throws: (any Error).self) {
      try await catalog.save(ProjectTask(projectID: ProjectID(), name: "Orphan"))
    }
  }

  @Test
  func tagsAreFoundByNameIgnoringCase() async throws {
    let first = try await catalog.tag(named: "Kunde A")
    let again = try await catalog.tag(named: " kunde a ")
    #expect(first == again)
    #expect(try await catalog.load().tags.count == 1)
  }

  @Test
  func tagsOnEntriesAreReplaced() async throws {
    let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: ManualClock(now))
    let a = try await engine.start(EntryDraft(title: "A"), mode: .parallel).value
    let b = try await engine.start(EntryDraft(title: "B"), mode: .parallel).value
    let urgent = try await catalog.tag(named: "dringend")
    let customer = try await catalog.tag(named: "Kunde")

    try await catalog.setTags([urgent.id, customer.id], on: [a, b])
    try await catalog.setTags([customer.id], on: [b])

    let tags = try await catalog.tags(of: [a, b])
    #expect(tags[a]?.map(\.name) == ["dringend", "Kunde"])
    #expect(tags[b]?.map(\.name) == ["Kunde"])
  }

  @Test
  func defaultCategoriesAreSeededOnce() async throws {
    let defaults = [
      EntryCategory(name: "Entwicklung", color: "#2563EB"),
      EntryCategory(name: "Meeting", color: "#C2410C"),
    ]
    #expect(try await catalog.seedDefaultCategories(defaults))
    #expect(try await catalog.seedDefaultCategories(defaults) == false)

    var loaded = try await catalog.load()
    #expect(loaded.categories.map(\.name) == ["Entwicklung", "Meeting"])

    // Archived defaults stay archived and are not seeded again.
    var meeting = try #require(loaded.categories.last)
    meeting.archived = true
    try await catalog.save(meeting)
    try await catalog.seedDefaultCategories(defaults)
    loaded = try await catalog.load()
    #expect(loaded.categories.count == 2)
    #expect(loaded.category(meeting.id)?.archived == true)
  }

  // MARK: Private

  private let database: AppDatabase
  private let catalog: CatalogStore
  private let now = Timestamp(milliseconds: 1_790_000_000_000)

}
