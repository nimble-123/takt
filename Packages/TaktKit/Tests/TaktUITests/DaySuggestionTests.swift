import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

// MARK: - DaySuggestionTests

@MainActor
struct DaySuggestionTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults()
    let database = try AppDatabase.inMemory()
    let settings = AppSettings(defaults: testDefaults.defaults)
    settings.calendarEnabled = true
    cache = CalendarEventCache(database: database)
    rules = SeriesRuleStore(database: database)
    model = MainWindowModel(
      engine: TimerEngine(store: GRDBTimerStore(database: database), clock: clock),
      queries: EntryQueries(database: database),
      catalog: CatalogModel(store: CatalogStore(database: database), clock: clock),
      settings: settings,
      clock: clock,
    )
    model.calendarEvents = CalendarEvents(cache: cache, rules: rules, refresh: { })
  }

  // MARK: Internal

  @Test
  func pastEventsWithoutTimeAreSuggested() async throws {
    try await store([event("review", minutes: -90), event("later", minutes: 60)])
    await model.reload()

    #expect(model.calendarSuggestions.map(\.id) == ["review"])
  }

  @Test
  func adoptingCreatesACalendarEntryOverTheEvent() async throws {
    let review = event("review", minutes: -90, series: "s1")
    try await store([review])
    await model.reload()

    let id = try #require(await model.adopt(review))

    let entry = try #require(model.entry(id))
    #expect(entry.entry.title == "review")
    #expect(entry.segments.first?.start == review.start)
    #expect(entry.segments.first?.end == review.end)
    #expect(entry.segments.first?.source == .calendar)
    #expect(model.calendarSuggestions.isEmpty)
  }

  @Test
  func suggestionsNeedTheCalendarTurnedOn() async throws {
    try await store([event("review", minutes: -90)])
    model.settings?.calendarEnabled = false
    await model.reload()

    #expect(model.calendarSuggestions.isEmpty)
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000)) // Wed 2026-10-07 10:00 Berlin
  private let testDefaults: TestDefaults
  private let cache: CalendarEventCache
  private let rules: SeriesRuleStore
  private let model: MainWindowModel

  private func event(_ id: String, minutes: Int64, series: String? = nil) -> CalendarEvent {
    let start = Timestamp(milliseconds: clock.now().milliseconds + minutes * 60_000)
    return CalendarEvent(
      id: id,
      seriesID: series,
      title: id,
      start: start,
      end: start.adding(seconds: 30 * 60),
      attendeeCount: 0,
      isOnlineMeeting: false,
      isPrivate: false,
    )
  }

  private func store(_ events: [CalendarEvent]) async throws {
    try await cache.replace(events, from: clock.now().adding(seconds: -86400), to: clock.now().adding(seconds: 86400))
  }
}
