import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

/// Tokens in the start input: `@category`, `/project/task`, `#tag` (MB-09).
@MainActor
struct StartTokensTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults()
    let database = try AppDatabase.inMemory()
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    catalog = CatalogModel(store: CatalogStore(database: database), clock: clock)
    model = MenuBarModel(
      engine: engine,
      queries: EntryQueries(database: database),
      catalog: catalog,
      clock: clock,
      settings: AppSettings(defaults: testDefaults.defaults),
    )
  }

  // MARK: Internal

  @Test
  func enterStartsWithCategoryProjectTaskAndTags() async throws {
    let review = try #require(await catalog.addCategory(named: "Code Review"))
    let project = try #require(await catalog.addProject(named: "Kundenportal"))
    let task = try #require(await catalog.addTask(named: "API-Dokumentation", to: project.id))

    model.query = "Doku überarbeiten @codereview /kunden/api #release #Q3 "
    #expect(model.tokens.chips.allSatisfy { $0.resolved })
    await model.submit(alternate: false)
    try await sync()

    let running = try #require(model.snapshot.running.first?.entry)
    #expect(running.title == "Doku überarbeiten")
    #expect(running.categoryID == review.id)
    #expect(running.projectID == project.id)
    #expect(running.taskID == task.id)
    let tags = await catalog.tags(of: [running.id])[running.id]?.map(\.name)
    #expect(Set(tags ?? []) == ["release", "Q3"])
  }

  @Test
  func unknownCategoryAssignsNothingAndShowsAHint() async throws {
    _ = await catalog.addCategory(named: "Meeting")
    model.query = "Telefonat @xyz "
    let chip = try #require(model.tokens.chips.first)
    #expect(!chip.resolved)

    await model.submit(alternate: false)
    try await sync()
    let running = try #require(model.snapshot.running.first?.entry)
    #expect(running.title == "Telefonat")
    #expect(running.categoryID == nil)
  }

  @Test
  func enterTakesTheCompletionWhileATokenIsTyped() async throws {
    _ = await catalog.addCategory(named: "Meeting")
    _ = await catalog.addCategory(named: "Support")

    model.query = "Daily @mee"
    #expect(model.completions.map(\.title) == ["Meeting"])
    await model.submit(alternate: false)
    try await sync()

    #expect(model.query == "Daily @Meeting ")
    #expect(model.snapshot.entries.isEmpty)
  }

  @Test
  func escClosesCompletionsUntilTheQueryChanges() async {
    _ = await catalog.addCategory(named: "Meeting")
    model.query = "Daily @"
    #expect(!model.completions.isEmpty)
    #expect(model.dismissCompletions())
    #expect(model.completions.isEmpty)
    model.query = "Daily @m"
    #expect(!model.completions.isEmpty)
  }

  @Test
  func arrowsMoveThroughCompletions() async {
    _ = await catalog.addProject(named: "Alpha")
    _ = await catalog.addProject(named: "Beta")
    model.query = "X /"
    #expect(model.completions.count == 2)
    model.moveSelection(by: 1)
    #expect(model.completionSelection == 1)
    model.moveSelection(by: 1)
    #expect(model.completionSelection == 0)
    #expect(model.selection == nil)
  }

  @Test
  func newTagIsOfferedNextToExistingOnes() throws {
    model.query = "X #rel"
    let completion = try #require(model.completions.last)
    #expect(completion.token == .tag("rel"))
    #expect(completion.subtitle != nil)
  }

  @Test
  func tokensOverrideTheSelectedSuggestion() async throws {
    let meeting = try #require(await catalog.addCategory(named: "Meeting"))
    let support = try #require(await catalog.addCategory(named: "Support"))
    let draft = EntryDraft(title: "Sprint-Planung", categoryID: meeting.id)
    let id = try await engine.start(draft, mode: .switchTo).value
    try await engine.stop(id)
    try await sync()

    model.query = "@support "
    let suggestion = try #require(model.suggestions.first)
    #expect(suggestion.draft.title == "Sprint-Planung")
    await model.start(suggestion: suggestion, parallel: false)
    try await sync()

    let running = try #require(model.snapshot.running.first?.entry)
    #expect(running.title == "Sprint-Planung")
    #expect(running.categoryID == support.id)
    #expect(model.query.isEmpty)
  }

  @Test
  func workItemNumbersAreNotTags() {
    model.query = "#4711 "
    #expect(model.tokens.chips.isEmpty)
    #expect(model.input.title == "#4711")
  }

  @Test
  func typedTagsComeFirstAndMergeWithRuleTags() {
    #expect(StartTokens.merged(["Release", "x"], ["release", "fix"]) == ["Release", "x", "fix"])
  }

  @Test
  func aNewProjectDropsTheOldTask() {
    let old = ProjectID()
    let new = ProjectID()
    var tokens = StartTokens()
    tokens.projectID = new
    let draft = tokens.applied(to: EntryDraft(title: "T", projectID: old, taskID: TaskID()))
    #expect(draft.projectID == new)
    #expect(draft.taskID == nil)
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000))
  private let testDefaults: TestDefaults
  private let engine: TimerEngine
  private let model: MenuBarModel
  private let catalog: CatalogModel

  private func sync() async throws {
    var updates = try await engine.updates().makeAsyncIterator()
    if let snapshot = await updates.next() {
      await model.receive(snapshot)
    }
  }

}
