import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

// MARK: - CalendarSuggestionTests

@MainActor
struct CalendarSuggestionTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults()
    let database = try AppDatabase.inMemory()
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    model = MenuBarModel(
      engine: engine,
      queries: EntryQueries(database: database),
      catalog: CatalogModel(store: CatalogStore(database: database), clock: clock),
      clock: clock,
      settings: AppSettings(defaults: testDefaults.defaults),
    )
    let cache = CalendarEventCache(database: database)
    self.cache = cache
    model.calendarEvents = CalendarEvents(
      search: { text, now in try await cache.search(text, at: now) },
      refresh: { },
    )
  }

  // MARK: Internal

  @Test
  func calendarHitsComeFirst() async throws {
    try await store([event("daily", "Daily", minutes: 30)])
    model.query = "Daily"
    await model.calendarTask?.value

    let first = try #require(model.suggestions.first)
    #expect(first.group == .calendar)
    #expect(first.event?.id == "daily")
    #expect(first.draft.title == "Daily")
  }

  @Test
  func emptySearchShowsOnlyCurrentEvents() async throws {
    try await store([
      event("now", "Läuft", minutes: -5),
      event("soon", "Gleich", minutes: 10),
      event("later", "Später", minutes: 60),
    ])
    model.popoverDidOpen()
    // Opening searches at once and again after the refresh; the second search replaces the first.
    for _ in 0..<50 where model.calendarResults.isEmpty {
      await Task.yield()
      await model.calendarTask?.value
    }

    #expect(model.currentEvents.map(\.id) == ["now", "soon"])
    #expect(!model.suggestions.contains { $0.group == .calendar })
  }

  @Test
  func eventThatBeganMinutesAgoStartsAtItsBeginning() async throws {
    let daily = event("daily", "Daily", minutes: -8)
    await model.start(event: daily, parallel: false)
    try await sync()

    let segment = try #require(model.snapshot.running.first?.openSegment)
    #expect(segment.start == daily.start)
    #expect(segment.source == .calendar)
  }

  @Test
  func eventThatBeganLongAgoStartsNow() async throws {
    await model.start(event: event("daily", "Daily", minutes: -20), parallel: false)
    try await sync()

    #expect(model.snapshot.running.first?.openSegment?.start == clock.now())
  }

  @Test
  func privateEventStartsWithoutItsTitle() async throws {
    await model.start(event: event("p", "", minutes: 0, isPrivate: true), parallel: false)
    try await sync()

    #expect(model.snapshot.running.first?.entry.title == String(localized: "Private", bundle: .module))
  }

  @Test
  func badgeSaysHowLongTheEventRunsOrWhenItStarts() {
    let now = clock.now()
    #expect(CalendarEventText.badge(for: event("a", "A", minutes: -2), at: now)?.contains("2") == true)
    #expect(CalendarEventText.badge(for: event("b", "B", minutes: 5), at: now)?.contains("5") == true)
    #expect(CalendarEventText.badge(for: event("c", "C", minutes: 60), at: now) == nil)
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000))
  private let testDefaults: TestDefaults
  private let engine: TimerEngine
  private let model: MenuBarModel
  private let cache: CalendarEventCache

  private func event(_ id: String, _ title: String, minutes: Int64, isPrivate: Bool = false) -> CalendarEvent {
    let start = Timestamp(milliseconds: clock.now().milliseconds + minutes * 60_000)
    return CalendarEvent(
      id: id,
      seriesID: nil,
      title: title,
      start: start,
      end: start.adding(seconds: 30 * 60),
      attendeeCount: 0,
      isOnlineMeeting: false,
      isPrivate: isPrivate,
    )
  }

  private func store(_ events: [CalendarEvent]) async throws {
    try await cache.replace(
      events,
      from: clock.now().adding(seconds: -86400),
      to: clock.now().adding(seconds: 86400),
    )
  }

  private func sync() async throws {
    var updates = try await engine.updates().makeAsyncIterator()
    if let snapshot = await updates.next() {
      await model.receive(snapshot)
    }
  }
}
