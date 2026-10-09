import Foundation
import Synchronization
import TaktADO
import TaktCore
import TaktStore
import TaktSystem
import Testing

@testable import TaktUI

// MARK: - FakeWorkItems

/// Answers searches from memory; counts the remote calls.
final class FakeWorkItems: WorkItemSource {

  // MARK: Lifecycle

  init(local: [WorkItemLink] = [], remote: [WorkItemLink] = [], suggested: [WorkItemLink] = []) {
    self.local = local
    self.remote = remote
    self.suggested = suggested
  }

  // MARK: Internal

  let local: [WorkItemLink]
  let remote: [WorkItemLink]
  let suggested: [WorkItemLink]

  var remoteSearches: Int {
    calls.withLock { $0 }
  }

  func cached(_: String) async throws -> [WorkItemLink] {
    local
  }

  func search(_: String) async throws -> [WorkItemLink] {
    calls.withLock { $0 += 1 }
    return remote
  }

  func suggestions(projects _: [String: [String]]) async throws -> [WorkItemLink] {
    suggested
  }

  func recentlyUsed() async throws -> [WorkItemLink] {
    []
  }

  func link(_ id: WorkItemLinkID) async throws -> WorkItemLink? {
    (local + remote + suggested).first { $0.id == id }
  }

  // MARK: Private

  private let calls = Mutex(0)

}

// MARK: - WorkItemSearchModelTests

@MainActor
struct WorkItemSearchModelTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults("takt-wi")
    database = try AppDatabase.inMemory()
    catalog = CatalogModel(store: CatalogStore(database: database), clock: clock)
  }

  // MARK: Internal

  @Test
  func cachedHitsAppearAtOnceAndFreshOnesAfterTheDelay() async {
    let source = FakeWorkItems(local: [item(1, "Login alt")], remote: [item(2, "Login neu"), item(1, "Login alt")])
    let model = model(source)

    model.query = "login"
    for _ in 0..<20 where model.workItemResults.isEmpty { await Task.yield() }
    #expect(model.workItemResults.map(\.workItemID) == [1])
    #expect(source.remoteSearches == 0)

    await settle(model)
    #expect(model.workItemResults.map(\.workItemID) == [2, 1])
    #expect(source.remoteSearches == 1)
    #expect(model.suggestions.first?.group == .azureDevOps)
  }

  @Test
  func typingQuicklySearchesOnlyOnce() async throws {
    let source = FakeWorkItems(remote: [item(1, "Login")])
    let model = model(source)
    for text in ["l", "lo", "log", "logi", "login"] { model.query = text }
    await settle(model)
    // Give a wrongly scheduled second search time to show up.
    try await Task.sleep(for: MenuBarModel.searchDelay * 2)
    #expect(source.remoteSearches == 1)
  }

  @Test
  func workItemTimerIsLinkedAndInTheTakenOverProject() async {
    await catalog.save(
      Project(
        name: "Portal",
        color: "#2563EB",
        source: .ado,
        adoOrganization: "contoso",
        adoProject: "Portal",
        createdAt: clock.now(),
      )
    )
    let model = model(FakeWorkItems())
    let draft = model.draft(for: item(1234, "Token-Refresh"))
    #expect(draft.title == "Token-Refresh")
    #expect(draft.projectID == catalog.catalog.projects.first?.id)
    #expect(draft.workItemLinkID != nil)
  }

  @Test
  func spacePreviewsOnlyASelectedWorkItem() async {
    let source = FakeWorkItems(remote: [item(1, "Login")])
    let model = model(source)
    model.query = "login"
    await settle(model)

    #expect(!model.togglePreview()) // nothing selected: Space types a space
    model.moveSelection(by: 1)
    #expect(model.togglePreview())
    #expect(model.previewedItem?.workItemID == 1)
    #expect(model.selectedWorkItemURL?.absoluteString == "https://dev.azure.com/contoso/Portal/_workitems/edit/1")
  }

  @Test
  func selectionStaysOnItsItemWhenFreshResultsArrive() async {
    let source = FakeWorkItems(local: [item(1, "Login alt")], remote: [item(2, "Login neu"), item(1, "Login alt")])
    let model = model(source)
    model.query = "login"
    for _ in 0..<20 where model.workItemResults.isEmpty { await Task.yield() }
    model.moveSelection(by: 1)

    // The fresh hit is inserted above the highlighted one.
    await settle(model)

    #expect(model.workItemResults.map(\.workItemID) == [2, 1])
    #expect(model.selectedWorkItemURL?.absoluteString == "https://dev.azure.com/contoso/Portal/_workitems/edit/1")
  }

  @Test
  func suggestionsAreLoadedOnOpenAndNotRepeatedWithinFiveMinutes() async {
    let model = model(FakeWorkItems(suggested: [item(7, "Aktuelle Iteration")]))
    await model.loadSuggestedWorkItems()
    #expect(model.suggestedWorkItems.map(\.workItemID) == [7])
  }

  // MARK: Private

  private let clock = ManualClock()
  private let testDefaults: TestDefaults
  private let database: AppDatabase
  private let catalog: CatalogModel

  private func item(_ id: Int, _ title: String) -> WorkItemLink {
    WorkItemLink(organization: "contoso", project: "Portal", workItemID: id, cachedTitle: title, cachedType: "Task")
  }

  private func model(_ source: FakeWorkItems) -> MenuBarModel {
    MenuBarModel(
      engine: TimerEngine(store: GRDBTimerStore(database: database), clock: clock),
      queries: EntryQueries(database: database),
      catalog: catalog,
      clock: clock,
      settings: AppSettings(defaults: testDefaults.defaults),
      workItems: source,
    )
  }

  /// Waits until the debounced remote search has run and its results are shown.
  private func settle(_ model: MenuBarModel) async {
    await model.searchTask?.value
  }

}

extension WorkItemSearchModelTests {

  // MARK: Internal

  @Test
  func recentlyCheckedOutBranchIsSuggestedFirst() async {
    let fromBranch = item(1234, "Login")
    let source = FakeWorkItems(remote: [fromBranch], suggested: [item(7, "Iteration")])
    let branch = GitBranch(
      repository: URL(filePath: "/tmp/portal"),
      name: "feature/1234-login",
      switchedAt: clock.now().adding(seconds: -600),
    )
    let model = model(source, branches: [branch])

    await model.loadSuggestedWorkItems()

    #expect(model.suggestedWorkItems.map(\.workItemID) == [1234, 7])
    #expect(model.suggestionReasons[fromBranch.id] == "From branch feature/1234-login")
  }

  @Test
  func oldBranchSwitchesAreIgnored() async {
    let branch = GitBranch(
      repository: URL(filePath: "/tmp/portal"),
      name: "feature/1234-login",
      switchedAt: clock.now().adding(seconds: -13 * 3600),
    )
    let model = model(
      FakeWorkItems(remote: [item(1234, "Login")], suggested: [item(7, "Iteration")]),
      branches: [branch],
    )
    await model.loadSuggestedWorkItems()
    #expect(model.suggestedWorkItems.map(\.workItemID) == [7])
  }

  // MARK: Private

  private func model(_ source: FakeWorkItems, branches: [GitBranch]) -> MenuBarModel {
    MenuBarModel(
      engine: TimerEngine(store: GRDBTimerStore(database: database), clock: clock),
      queries: EntryQueries(database: database),
      catalog: catalog,
      clock: clock,
      settings: AppSettings(defaults: testDefaults.defaults),
      workItems: source,
      gitBranches: { branches },
    )
  }

}
