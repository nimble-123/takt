import TaktCore
import Testing

@testable import TaktStore

// MARK: - SeriesRuleStoreTests

struct SeriesRuleStoreTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    store = SeriesRuleStore(database: database)
  }

  // MARK: Internal

  @Test
  func savedRuleRoundTrips() async throws {
    let project = Project(name: "Plattform", color: "#2563EB", icon: "globe", createdAt: now)
    let category = EntryCategory(name: "Meeting", color: "#888888")
    try await CatalogStore(database: database).save(project)
    try await CatalogStore(database: database).save(category)
    let rule = SeriesRule(
      seriesID: "series-1",
      projectID: project.id,
      categoryID: category.id,
      offersTimerAtStart: true,
      endsWithEvent: true,
    )

    try await store.save(rule, at: now)

    #expect(try await store.all() == [rule])
  }

  @Test
  func savingAgainReplacesTheRule() async throws {
    let category = EntryCategory(name: "Meeting", color: "#888888")
    try await CatalogStore(database: database).save(category)
    try await store.save(SeriesRule(seriesID: "series-1", categoryID: category.id), at: now)
    try await store.save(SeriesRule(seriesID: "series-1"), at: now)

    #expect(try await store.all().isEmpty)
  }

  @Test
  func ruleAppliesOnlyWhereTheDraftHasNothing() {
    let project = ProjectID()
    let category = CategoryID()
    let draft = SeriesRule(seriesID: "s", projectID: ProjectID(), categoryID: category)
      .applied(to: EntryDraft(title: "Daily", projectID: project))

    #expect(draft.projectID == project)
    #expect(draft.categoryID == category)
  }

  // MARK: Private

  private let now = Timestamp(milliseconds: 1_790_000_000_000)
  private let database: AppDatabase
  private let store: SeriesRuleStore
}
