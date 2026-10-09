import Foundation
import Synchronization
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

// MARK: - MainWindowModelTests

@MainActor
struct MainWindowModelTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    calendar.firstWeekday = 2
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    model = MainWindowModel(
      engine: engine,
      queries: EntryQueries(database: database),
      catalog: CatalogModel(store: CatalogStore(database: database), clock: clock),
      clock: clock,
      calendar: calendar,
    )
    // Tests open undo groups themselves; in the app the event loop does it.
    undoManager.groupsByEvent = false
  }

  // MARK: Internal

  @Test
  func drawnEntryIsCreatedAndSelected() async throws {
    let id = try #require(await model.createEntry(from: at(8), to: at(9)))
    #expect(model.selection == [id])
    #expect(model.entry(id)?.segments.first?.source == .manual)
    #expect(model.dayTotal == 3600)
  }

  @Test
  func stopAllFromTheWindowBooksAutomatically() async throws {
    var reported = [[EntryID]]()
    model.actions.onStopped = { reported.append($0) }
    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    _ = try await engine.start(EntryDraft(title: "B"), mode: .parallel)

    await model.stopAll()

    #expect(reported.map(\.count) == [2])
    #expect(try await engine.snapshot().entries.isEmpty)
  }

  @Test
  func workItemTimerFromThePaletteIsInTheTakenOverProject() async throws {
    await model.catalog.save(
      Project(
        name: "Portal",
        color: "#2563EB",
        source: .ado,
        adoOrganization: "contoso",
        adoProject: "Portal",
        createdAt: clock.now(),
      )
    )
    let stored = try await WorkItemCache(database: database).store([
      WorkItemLink(organization: "contoso", project: "Portal", workItemID: 1234, cachedTitle: "Token")
    ])
    let item = try #require(stored.first)

    await model.startTimer(for: item)

    let running = try #require(try await engine.snapshot().running.first)
    #expect(running.entry.projectID == model.catalog.catalog.projects.first?.id)
    #expect(running.entry.workItemLinkID == item.id)
  }

  @Test
  func undoAndRedoGoThroughTheUndoManager() async {
    await withUndoGroup { await model.createEntry(from: at(8), to: at(9)) }
    #expect(model.data.entries.count == 1)
    #expect(undoManager.undoActionName == "New Entry")

    await step { undoManager.undo() }
    #expect(model.data.entries.isEmpty)
    #expect(undoManager.canRedo)

    await step { undoManager.redo() }
    #expect(model.data.entries.count == 1)
  }

  @Test
  func moveAndUndoRestoresTheTime() async throws {
    let id = try #require(await model.createEntry(from: at(8), to: at(9)))
    let segment = try #require(model.entry(id)?.segments.first)
    await withUndoGroup { await model.move(segment, by: 1800) }
    #expect(model.entry(id)?.segments.first?.start == at(8.5))

    await step { undoManager.undo() }
    #expect(model.entry(id)?.segments.first?.start == at(8))
  }

  @Test
  func invalidEditShowsAMessageAndChangesNothing() async throws {
    let id = try #require(await model.createEntry(from: at(8), to: at(9)))
    let segment = try #require(model.entry(id)?.segments.first)
    await model.setBounds(of: segment, start: at(9), end: at(8))

    #expect(model.errorMessage != nil)
    #expect(model.entry(id)?.segments.first == segment)
  }

  @Test
  func boundsThatOverlapAnotherSegmentAreRejected() async throws {
    let id = try await entry(withSegments: [(7, 8), (9, 10)])
    let before = try #require(model.entry(id)?.segments)

    await model.setBounds(of: before[1], start: at(7.5), end: at(10))

    #expect(model.errorMessage != nil)
    #expect(model.entry(id)?.segments == before)
  }

  @Test
  func moveOntoAnotherSegmentIsRejected() async throws {
    let id = try await entry(withSegments: [(7, 8), (9, 10)])
    let before = try #require(model.entry(id)?.segments)

    await model.move(before[1], by: -1.5 * 3600)

    #expect(model.errorMessage != nil)
    #expect(model.entry(id)?.segments == before)
  }

  @Test
  func closeGapOverAnotherSegmentIsRejected() async throws {
    let id = try await entry(withSegments: [(7, 8), (8.5, 9), (9.5, 10)])
    let before = try #require(model.entry(id)?.segments)

    await model.closeGap(between: before[0], and: before[2])

    #expect(model.errorMessage != nil)
    #expect(model.entry(id)?.segments == before)
  }

  @Test
  func boundsWithoutEndKeepAClosedSegmentClosed() async throws {
    let id = try #require(await model.createEntry(from: at(8), to: at(9)))
    let segment = try #require(model.entry(id)?.segments.first)

    await model.setBounds(of: segment, start: at(7), end: nil)

    #expect(model.errorMessage != nil)
    #expect(model.entry(id)?.segments == [segment])
  }

  @Test
  func deleteRemovesSelectedEntries() async throws {
    let a = try #require(await model.createEntry(from: at(7), to: at(8)))
    let b = try #require(await model.createEntry(from: at(8), to: at(9)))
    model.selection = [a, b]
    await model.delete(model.selection)

    #expect(model.data.entries.isEmpty)
    #expect(model.selection.isEmpty)
  }

  @Test(arguments: [MainWindowModel.Section.analytics, .projects, .settings])
  func deleteKeyLeavesEntriesAloneOnScreensWithoutThem(section: MainWindowModel.Section) async throws {
    let id = try #require(await model.createEntry(from: at(7), to: at(8)))
    model.selection = [id]
    model.section = section

    await model.deleteSelection()

    #expect(model.data.entries.map(\.id) == [id])
  }

  @Test
  func deleteKeyRemovesTheSelectionOnEntryScreens() async throws {
    let id = try #require(await model.createEntry(from: at(7), to: at(8)))
    model.selection = [id]
    model.section = .week

    await model.deleteSelection()

    #expect(model.data.entries.isEmpty)
  }

  @Test
  func bulkCountingModeChangesAllSelected() async throws {
    let a = try #require(await model.createEntry(from: at(7), to: at(8)))
    let b = try #require(await model.createEntry(from: at(8), to: at(9)))
    await model.update([a, b], name: "Change Counting") { $0.countingMode = .full }

    #expect(model.data.entries.allSatisfy { $0.entry.countingMode == .full })
  }

  @Test
  func quickEditsOfOneEntryDoNotConflict() async throws {
    let id = try #require(await model.createEntry(from: at(7), to: at(8)))

    // E.g. the title commits on blur while the click on the category picker saves.
    let rename = Task { await model.update([id], name: "Rename") { $0.title = "Renamed" } }
    let weigh = Task { await model.update([id], name: "Change Weight") { $0.weight = 2 } }
    await rename.value
    await weigh.value

    #expect(model.errorMessage == nil)
    #expect(model.entry(id)?.entry.title == "Renamed")
    #expect(model.entry(id)?.entry.weight == 2)
  }

  @Test
  func splitSelectsTheLaterPart() async throws {
    let id = try #require(await model.createEntry(from: at(7), to: at(9)))
    await model.split(id, at: at(8))

    #expect(model.data.entries.count == 2)
    #expect(model.selection.count == 1 && !model.selection.contains(id))
  }

  @Test
  func splitKeepsTheTags() async throws {
    let id = try #require(await model.createEntry(from: at(7), to: at(9)))
    await model.catalog.setTags(named: ["Review"], on: [id])

    await model.split(id, at: at(8))

    let later = try #require(model.selection.first)
    #expect(await model.catalog.tags(of: [later])[later]?.map(\.name) == ["Review"])
  }

  @Test
  func splitOfEntryInGlobalPauseIsResumedWithIt() async throws {
    clock.set(at(7))
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.set(at(9))
    let pauseID = try #require(try await engine.pauseAll().value)
    await model.reload()

    await model.split(id, at: at(8))
    let later = try #require(model.selection.first)
    try await engine.resumeAll(pauseID)

    #expect(try await engine.snapshot().running.map(\.id) == [later])
  }

  @Test
  func splitOfEntryPausedByIdleIsResumedByTheDecision() async throws {
    clock.set(at(7))
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.set(at(9.5))
    let event = try #require(try await engine.recordIdle(from: at(9), to: at(9.5)))
    await model.reload()

    await model.split(id, at: at(8))
    let later = try #require(model.selection.first)
    try await engine.resolveIdle(event.id, .discard)

    #expect(try await engine.snapshot().running.map(\.id) == [later])
  }

  @Test
  func pausesBetweenSegmentsAreSummedForTheDay() async throws {
    clock.set(at(7))
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.set(at(8))
    try await engine.pause(id)
    clock.set(at(8.5))
    try await engine.resume(id, mode: .switchTo)
    clock.set(at(9))
    try await engine.stop(id)
    await model.reload()

    #expect(model.dayPauses == 1800)
    #expect(model.dayTotal == 1.5 * 3600)
  }

  @Test
  func layoutIsCachedUntilTheDataChanges() async throws {
    _ = try #require(await model.createEntry(from: at(8), to: at(9)))
    let first = model.layout(for: model.dayRange, now: at(12))
    // Without a running timer, `now` does not matter: the cached layout answers.
    #expect(model.layout(for: model.dayRange, now: at(13)) == first)
    #expect(first.items.count == 1)

    _ = try #require(await model.createEntry(from: at(9), to: at(9.5)))

    #expect(model.layout(for: model.dayRange, now: at(12)).items.count == 2)
  }

  @Test
  func runningLayoutFollowsNow() async throws {
    clock.set(at(8))
    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    await model.reload()

    let early = model.layout(for: model.dayRange, now: at(9))
    let late = model.layout(for: model.dayRange, now: at(10))

    #expect(early.items.first?.end == at(9))
    #expect(late.items.first?.end == at(10))
  }

  @Test
  func entryLookupFollowsReloads() async throws {
    let id = try #require(await model.createEntry(from: at(8), to: at(9)))
    #expect(model.entry(id)?.entry.title == model.data.entries.first?.entry.title)

    await model.delete([id])

    #expect(model.entry(id) == nil)
  }

  @Test
  func olderReloadDoesNotOverwriteNewerData() async {
    let stale = TimelineData(entries: [
      EntryWithSegments(entry: TimeEntry(title: "Stale", createdAt: at(8), updatedAt: at(8)), segments: [])
    ])
    let calls = Mutex(0)
    let (release, releaseOlder) = AsyncStream.makeStream(of: Void.self)
    model.loadTimeline = { @Sendable _, _ in
      let call = calls.withLock { count in
        count += 1
        return count
      }
      guard call == 1 else { return TimelineData() }
      // The first reload answers last, with what it read before the newer one.
      for await _ in release { break }
      return stale
    }

    let older = Task { await model.reload() }
    for _ in 0..<200 where calls.withLock({ $0 }) == 0 { await Task.yield() }
    await model.reload()
    releaseOlder.yield()
    await older.value

    #expect(model.data == TimelineData())
  }

  @Test
  func weekHasSevenDaysStartingMonday() {
    model.section = .week
    #expect(model.weekDays.count == 7)
    #expect(model.weekRange.lowerBound == at(-48))
  }

  @Test
  func stepMovesByDayOrWeek() {
    let start = model.dayRange.lowerBound
    model.step(by: 1)
    #expect(model.dayRange.lowerBound == start.adding(seconds: 24 * 3600))
    model.section = .week
    model.step(by: -1)
    #expect(model.dayRange.lowerBound == start.adding(seconds: -6 * 24 * 3600))
  }

  @Test
  func dayCloseStepsByOneDay() {
    let start = model.dayRange.lowerBound
    model.section = .dayClose
    model.step(by: 1)
    #expect(model.dayRange.lowerBound == start.adding(seconds: 24 * 3600))
  }

  @Test
  func openingAnEntryShowsTheInspectorWithOnlyThatEntry() async throws {
    let first = try await engine.start(EntryDraft(title: "A"), mode: .parallel).value
    let second = try await engine.start(EntryDraft(title: "B"), mode: .parallel).value
    model.selection = [first, second]
    model.isInspectorShown = false

    model.openInspector(for: second)

    #expect(model.selection == [second])
    #expect(model.isInspectorShown)
    #expect(model.showsInspector)
  }

  @Test
  func rightClickActsOnTheSelectionOnlyWhenTheEntryIsPartOfIt() {
    let first = EntryID()
    let second = EntryID()
    let other = EntryID()
    model.selection = [first, second]
    #expect(model.contextTargets(for: second) == [first, second])
    #expect(model.contextTargets(for: other) == [other])
  }

  @Test(arguments: [MainWindowModel.Section.today, .dayClose, .week, .entries])
  func inspectorIsAvailableOnEntryScreens(section: MainWindowModel.Section) {
    model.section = section
    #expect(model.showsInspector)
    model.isInspectorShown = false
    #expect(!model.showsInspector)
  }

  @Test(arguments: [MainWindowModel.Section.analytics, .projects, .settings])
  func inspectorIsHiddenOnOtherScreens(section: MainWindowModel.Section) {
    model.section = section
    #expect(!model.hasInspector)
    #expect(!model.showsInspector)
    // The user's choice survives screens without an inspector.
    #expect(model.isInspectorShown)
  }

  @Test
  func searchHidesTheInspector() {
    model.section = .today
    model.searchText = "login"
    #expect(!model.hasInspector)
    model.searchText = ""
    #expect(model.showsInspector)
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000)) // Wed 2026-10-07 10:00 Berlin
  private let database: AppDatabase
  private let engine: TimerEngine
  private let model: MainWindowModel
  private let undoManager = UndoManager()

  private func at(_ hours: Double) -> Timestamp {
    model.dayRange.lowerBound.adding(seconds: hours * 3600)
  }

  /// A stopped entry with closed manual segments from and to the given hours.
  private func entry(withSegments hours: [(Double, Double)]) async throws -> EntryID {
    let entry = TimeEntry(title: "A", createdAt: clock.now(), updatedAt: clock.now())
    let segments = hours.map { Segment(entryID: entry.id, start: at($0.0), end: at($0.1), source: .manual) }
    try await engine.apply([.entry(before: nil, after: entry)] + segments.map { .segment(before: nil, after: $0) })
    await model.reload()
    return entry.id
  }

  /// Runs one undo or redo step and waits until the engine has applied it.
  private func step(_ action: () -> Void) async {
    let before = model.data
    action()
    for _ in 0..<200 where model.data == before {
      await Task.yield()
      await model.reload()
    }
  }

  private func withUndoGroup(_ body: () async -> Void) async {
    model.undoManager = undoManager
    undoManager.beginUndoGrouping()
    await body()
    undoManager.endUndoGrouping()
  }

}

// MARK: - MainWindowSearchTests

@MainActor
struct MainWindowSearchTests {

  // MARK: Internal

  @Test
  func searchFindsEntriesAndRevealJumpsToTheirDay() async throws {
    let database = try AppDatabase.inMemory()
    let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    let model = MainWindowModel(
      engine: engine,
      queries: EntryQueries(database: database),
      catalog: CatalogModel(store: CatalogStore(database: database), clock: clock),
      search: SearchIndex(database: database),
      clock: clock,
    )
    let (entry, changes) = try EntryEdits.create(
      EntryDraft(title: "Release vorbereiten", note: "Changelog prüfen"),
      from: clock.now().adding(seconds: -10 * 86_400),
      to: clock.now().adding(seconds: -10 * 86_400 + 3600),
      now: clock.now(),
    )
    try await engine.apply(changes)

    model.searchText = "changelog"
    await model.searchTask?.value
    let hit = try #require(model.searchResults.entries.first)
    #expect(hit.entry.id == entry.id)
    #expect(hit.snippet == "**Changelog** prüfen")

    model.reveal(hit.entry)
    #expect(model.section == .today)
    #expect(model.selection == [entry.id])
    #expect(model.dayRange.contains(clock.now().adding(seconds: -10 * 86_400)))
    #expect(model.searchText.isEmpty)
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000))

}
