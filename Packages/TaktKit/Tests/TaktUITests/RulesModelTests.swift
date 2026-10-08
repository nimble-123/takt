import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

@MainActor
struct RulesModelTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults("takt-rules")
    database = try AppDatabase.inMemory()
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    catalog = CatalogModel(store: CatalogStore(database: database), clock: clock)
    rules = RulesModel(store: RuleStore(database: database))
    bug = WorkItemLink(
      organization: "o",
      project: "Portal",
      workItemID: 7,
      cachedTitle: "Absturz",
      cachedType: "Bug",
    )
  }

  // MARK: Internal

  @Test
  func startingFromABugAppliesTheRule() async throws {
    let support = try await supportRule()
    try await storeBug()
    let source = FakeWorkItems(local: [bug])
    let menuBar = MenuBarModel(
      engine: engine,
      queries: EntryQueries(database: database),
      catalog: catalog,
      clock: clock,
      settings: AppSettings(defaults: testDefaults.defaults),
      workItems: source,
      rules: rules,
    )

    await menuBar.start(EntryDraft(title: "Absturz", workItemLinkID: bug.id), parallel: false)

    let running = try #require(try await engine.snapshot().running.first)
    #expect(running.entry.categoryID == support)
    #expect(await catalog.tags(of: [running.id])[running.id]?.map(\.name) == ["fix"])
  }

  @Test
  func linkingFillsOnlyEmptyFields() async throws {
    let support = try await supportRule()
    try await storeBug()
    let window = MainWindowModel(
      engine: engine,
      queries: EntryQueries(database: database),
      catalog: catalog,
      workItems: FakeWorkItems(local: [bug]),
      rules: rules,
      clock: clock,
    )
    let manual = try #require(catalog.catalog.categories.first { $0.name != "Support" })
    let free = try #require(await window.createEntry(from: clock.now().adding(seconds: -3600), to: clock.now()))
    let chosen = try #require(
      await window.createEntry(from: clock.now().adding(seconds: -7200), to: clock.now().adding(seconds: -3600))
    )
    await window.update([chosen], name: "x") { $0.categoryID = manual.id }

    await window.link([free, chosen], to: bug)

    #expect(window.entry(free)?.entry.categoryID == support)
    #expect(window.entry(chosen)?.entry.categoryID == manual.id)
    #expect(await catalog.tags(of: [free])[free]?.map(\.name) == ["fix"])
  }

  @Test
  func rulesCanBeReordered() async {
    let first = Rule(name: "A", conditions: [.titleContains("a")])
    let second = Rule(name: "B", conditions: [.titleContains("b")])
    await rules.save(first)
    await rules.save(second)
    await rules.move(second.id, by: -1)
    #expect(rules.rules.map(\.name) == ["B", "A"])
    await rules.reload()
    #expect(rules.rules.map(\.name) == ["B", "A"])
  }

  @Test
  func exampleRuleUsesTheSupportCategory() async throws {
    await catalog.seedDefaults()
    await rules.addExample(categories: catalog.activeCategories)
    let rule = try #require(rules.rules.first)
    #expect(rule.conditions == [.workItemType("Bug")])
    #expect(catalog.catalog.category(rule.categoryID)?.name == "Support")
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000))
  private let testDefaults: TestDefaults
  private let database: AppDatabase
  private let engine: TimerEngine
  private let catalog: CatalogModel
  private let rules: RulesModel
  private let bug: WorkItemLink

  /// Entries reference work items by foreign key, so the work item must be stored first.
  private func storeBug() async throws {
    try await WorkItemCache(database: database).store([bug])
  }

  private func supportRule() async throws -> CategoryID {
    await catalog.seedDefaults()
    let support = try #require(catalog.catalog.categories.first { $0.name == "Support" })
    await rules.save(Rule(conditions: [.workItemType("Bug")], categoryID: support.id, tags: ["fix"]))
    return support.id
  }

}
