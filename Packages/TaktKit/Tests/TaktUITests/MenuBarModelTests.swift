import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

// MARK: - MenuBarModelTests

@MainActor
struct MenuBarModelTests {

  // MARK: Lifecycle

  init() throws {
    let database = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    catalog = CatalogModel(store: CatalogStore(database: database), clock: clock)
    model = MenuBarModel(
      engine: engine,
      queries: EntryQueries(database: database),
      catalog: catalog,
      clock: clock,
      settings: AppSettings(defaults: UserDefaults(suiteName: "takt-tests-\(UUID().uuidString)") ?? .standard),
      calendar: calendar,
    )
  }

  // MARK: Internal

  @Test
  func enterStartsTypedTitleAndSwitches() async throws {
    model.query = "Review"
    await model.submit(alternate: false)
    clock.advance(seconds: 60)
    model.query = "Ticket"
    await model.submit(alternate: false)
    try await sync()

    #expect(model.snapshot.running.map(\.entry.title) == ["Ticket"])
    #expect(model.snapshot.paused.map(\.entry.title) == ["Review"])
    #expect(model.query.isEmpty)
  }

  @Test
  func optionEnterStartsInParallel() async throws {
    model.query = "Meeting"
    await model.submit(alternate: false)
    model.query = "Ticket"
    await model.submit(alternate: true)
    try await sync()

    #expect(Set(model.snapshot.running.map(\.entry.title)) == ["Meeting", "Ticket"])
  }

  @Test
  func stopAllStopsEverythingAndReportsItOnce() async throws {
    var reported = [[EntryID]]()
    model.actions.onStopped = { reported.append($0) }
    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    _ = try await engine.start(EntryDraft(title: "B"), mode: .parallel)
    try await sync()

    await model.stopAll()
    try await sync()

    #expect(model.snapshot.entries.isEmpty)
    #expect(reported.map(\.count) == [2])
    #expect(model.canUndo)
  }

  @Test
  func reopeningThePopoverForgetsEarlierUndo() async {
    model.query = "Review"
    await model.submit(alternate: false)
    #expect(model.canUndo)

    model.popoverDidOpen()

    #expect(!model.canUndo)
  }

  @Test
  func reopeningKeepsTheUndoOfTheStopInTheToast() async throws {
    let id = try await engine.start(EntryDraft(title: "Review"), mode: .switchTo).value
    try await sync()
    await model.stop(id)
    #expect(model.toast?.id == id)

    model.popoverDidOpen()

    #expect(model.canUndo)
  }

  @Test
  func emptyQueryDoesNotStart() async throws {
    model.query = "   "
    await model.submit(alternate: false)
    try await sync()
    #expect(model.snapshot.entries.isEmpty)
  }

  @Test
  func searchFiltersRecentsAndArrowSelectsSuggestion() async throws {
    try await track("Bug 1234 Token", minutes: 10)
    try await track("Sprint-Planung", minutes: 10)
    try await sync()

    model.query = "token"
    #expect(model.suggestions.map(\.draft.title) == ["Bug 1234 Token"])
    model.moveSelection(by: 1)
    #expect(model.selection == 0)
    await model.submit(alternate: false)
    try await sync()
    #expect(model.snapshot.running.map(\.entry.title) == ["Bug 1234 Token"])
  }

  @Test
  func selectionWrapsBackToTypedText() async throws {
    try await track("A", minutes: 1)
    try await sync()
    model.query = "A"
    model.moveSelection(by: 1)
    model.moveSelection(by: 1)
    #expect(model.selection == nil)
    model.moveSelection(by: -1)
    #expect(model.selection == 0)
  }

  @Test
  func recentsShowFourAndCommandNumberStartsOne() async throws {
    for title in ["A", "B", "C", "D", "E"] { try await track(title, minutes: 1) }
    try await sync()

    #expect(model.suggestions.map(\.draft.title) == ["E", "D", "C", "B"])
    await model.startRecent(at: 1)
    try await sync()
    #expect(model.snapshot.running.map(\.entry.title) == ["D"])
  }

  @Test
  func pauseAllTogglesToResumeAll() async throws {
    await model.start(EntryDraft(title: "A"), parallel: false)
    await model.start(EntryDraft(title: "B"), parallel: true)
    clock.advance(seconds: 60)
    try await sync()

    await model.togglePauseAll()
    try await sync()
    #expect(model.snapshot.running.isEmpty)
    #expect(model.canResumeAll)

    await model.togglePauseAll()
    try await sync()
    #expect(model.snapshot.running.count == 2)
  }

  @Test
  func stopShowsToastAndUndoBringsTimerBack() async throws {
    await model.start(EntryDraft(title: "A"), parallel: false)
    clock.advance(seconds: 60)
    try await sync()
    let id = try #require(model.snapshot.running.first?.id)

    await model.stop(id)
    try await sync()
    #expect(model.toast?.title == "A")
    #expect(model.snapshot.entries.isEmpty)

    await model.undo()
    try await sync()
    #expect(model.snapshot.running.map(\.id) == [id])
    #expect(model.toast == nil)
  }

  @Test
  func stopAllIsUndoneAtOnce() async throws {
    await model.start(EntryDraft(title: "A"), parallel: false)
    await model.start(EntryDraft(title: "B"), parallel: true)
    clock.advance(seconds: 60)
    try await sync()

    await model.stopAll()
    try await sync()
    #expect(model.snapshot.entries.isEmpty)

    await model.undo()
    try await sync()
    #expect(model.snapshot.running.count == 2)
  }

  @Test
  func noteIsSavedOnStoppedEntry() async throws {
    await model.start(EntryDraft(title: "A"), parallel: false)
    clock.advance(seconds: 60)
    try await sync()
    let id = try #require(model.snapshot.running.first?.id)
    await model.stop(id)

    await model.saveNote("  Ursache gefunden ", for: id)

    #expect(try await model.queries.entry(id)?.note == "Ursache gefunden")
  }

  @Test
  func todayTotalCountsParallelTimeOnce() async throws {
    await model.start(EntryDraft(title: "A"), parallel: false)
    await model.start(EntryDraft(title: "B"), parallel: true)
    clock.advance(seconds: 1800)
    try await sync()

    #expect(model.todayTotal == 1800)
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000)) // 2026-10-07 10:00 Berlin
  private let engine: TimerEngine
  private let model: MenuBarModel
  private let catalog: CatalogModel

  /// Lets the model see the engine's state, as `run()` does in the app.
  private func sync() async throws {
    var updates = try await engine.updates().makeAsyncIterator()
    if let snapshot = await updates.next() {
      await model.receive(snapshot)
    }
  }

  private func track(_ title: String, minutes: Double) async throws {
    let id = try await engine.start(EntryDraft(title: title), mode: .switchTo).value
    clock.advance(seconds: minutes * 60)
    try await engine.stop(id)
  }

}

// MARK: - MenuBarStatusTests

struct MenuBarStatusTests {

  // MARK: Internal

  @Test
  func idleWithoutEntries() {
    let status = MenuBarStatus(snapshot: TimerSnapshot(), now: now)
    #expect(status.state == .idle)
    #expect(status.title == nil)
    #expect(status.symbolName == "stopwatch")
  }

  @Test
  func runningShowsNewestEntryTime() {
    let snapshot = TimerSnapshot(entries: [
      active(.running, startedSecondsAgo: 7200),
      active(.running, startedSecondsAgo: 65 * 60),
    ])
    let status = MenuBarStatus(snapshot: snapshot, now: now)
    #expect(status.state == .running)
    #expect(status.title == "1:05")
  }

  @Test
  func pausedOnlyHasNoTitle() {
    let status = MenuBarStatus(snapshot: TimerSnapshot(entries: [active(.paused, startedSecondsAgo: 60)]), now: now)
    #expect(status.state == .paused)
    #expect(status.title == nil)
    #expect(status.symbolName == "pause.circle")
  }

  @Test
  func durationFormats() {
    #expect(DurationText.clock(3 * 3600 + 7 * 60 + 9) == "3:07:09")
    #expect(DurationText.hoursMinutes(59) == "0:00")
    #expect(DurationText.hoursMinutes(-5) == "0:00")
    #expect(DurationText.span(24 * 60) == "24 min")
    #expect(DurationText.span(65 * 60) == "1 h 05 min")
  }

  // MARK: Private

  private let now = Timestamp(milliseconds: 10_000_000)

  private func active(_ state: EntryState, startedSecondsAgo: Double) -> ActiveEntry {
    let start = now.adding(seconds: -startedSecondsAgo)
    let entry = TimeEntry(title: "A", state: state, createdAt: start, updatedAt: start)
    let open = state == .running ? Segment(entryID: entry.id, start: start) : nil
    return ActiveEntry(entry: entry, openSegment: open, closedDuration: 0)
  }

}

extension MenuBarModelTests {
  @Test
  func pendingIdleIsShownAndResolved() async throws {
    await model.start(EntryDraft(title: "A"), parallel: false)
    let start = clock.now().adding(seconds: 600)
    clock.advance(seconds: 3000)
    _ = try await engine.recordIdle(from: start, to: clock.now())
    try await sync()
    #expect(model.pendingIdle?.start == start)

    await model.resolveIdle(.discard)
    try await sync()
    #expect(model.pendingIdle == nil)
    #expect(model.snapshot.running.map(\.entry.title) == ["A"])
  }
}

extension MenuBarModelTests {
  @Test
  func searchFindsLocalTasksWithProjectSubtitle() async throws {
    let project = try #require(await catalog.addProject(named: "Kundenportal"))
    _ = await catalog.addTask(named: "Login-Refactoring", to: project.id)

    model.query = "login"
    let suggestion = try #require(model.suggestions.first)
    #expect(suggestion.group == .localTask)
    #expect(suggestion.subtitle == "Kundenportal")

    model.moveSelection(by: 1)
    await model.submit(alternate: false)
    try await sync()
    let running = try #require(model.snapshot.running.first?.entry)
    #expect(running.title == "Login-Refactoring")
    #expect(running.projectID == project.id)
    #expect(running.taskID != nil)
  }

  @Test
  func todayIsSplitByCategory() async throws {
    await catalog.seedDefaults()
    let development = try #require(catalog.catalog.categories.first)
    await model.start(EntryDraft(title: "A", categoryID: development.id), parallel: false)
    clock.advance(seconds: 1800)
    await model.start(EntryDraft(title: "B"), parallel: false)
    clock.advance(seconds: 600)
    try await sync()

    #expect(model.todayByCategory.map(\.categoryID) == [development.id, nil])
    #expect(model.todayByCategory.map(\.seconds) == [1800, 600])
  }
}

extension MenuBarModelTests {
  @Test
  func enterUsesTheConfiguredStartMode() async throws {
    model.settings.startMode = .parallel
    model.query = "A"
    await model.submit(alternate: false)
    model.query = "B"
    await model.submit(alternate: false)
    try await sync()
    #expect(model.snapshot.running.count == 2)

    model.query = "C"
    await model.submit(alternate: true)
    try await sync()
    #expect(model.snapshot.running.map(\.entry.title) == ["C"])
  }
}
