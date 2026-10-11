import TaktCore
import Testing

@testable import TaktStore

// MARK: - CalendarEventCacheTests

struct CalendarEventCacheTests {

  // MARK: Lifecycle

  init() throws {
    cache = try CalendarEventCache(database: AppDatabase.inMemory())
  }

  // MARK: Internal

  @Test
  func eventsRoundTrip() async throws {
    let daily = event("a", "Daily", at: 9, series: "series-1", attendees: 6, online: true)
    try await cache.replace([daily], from: hour(0), to: hour(48))
    #expect(try await cache.events(from: hour(0), to: hour(24)) == [daily])
  }

  @Test
  func replaceDropsEventsMissingFromTheNewSync() async throws {
    try await cache.replace([event("a", "Daily", at: 9), event("b", "Review", at: 14)], from: hour(0), to: hour(48))
    try await cache.replace([event("b", "Review", at: 14)], from: hour(0), to: hour(48))
    #expect(try await cache.events(from: hour(0), to: hour(48)).map(\.id) == ["b"])
  }

  @Test
  func replaceKeepsOnlyTheWindow() async throws {
    try await cache.replace([event("a", "Früher", at: 1), event("b", "Drin", at: 30)], from: hour(24), to: hour(48))
    #expect(try await cache.events(from: hour(0), to: hour(72)).map(\.id) == ["b"])
  }

  @Test
  func privateTitlesAreNeverStored() async throws {
    try await cache.replace([event("a", "Arzttermin", at: 9, isPrivate: true)], from: hour(0), to: hour(24))
    let stored = try #require(try await cache.events(from: hour(0), to: hour(24)).first)
    #expect(stored.title.isEmpty)
    #expect(stored.isPrivate)
  }

  @Test
  func searchSkipsPastEventsAndMatchesTitles() async throws {
    try await cache.replace(
      [event("a", "Daily", at: 9), event("b", "Review 100%", at: 14), event("c", "Daily", at: 33)],
      from: hour(0),
      to: hour(48),
    )
    let now = hour(12)
    #expect(try await cache.search("", at: now).map(\.id) == ["b", "c"])
    #expect(try await cache.search("daily", at: now).map(\.id) == ["c"])
    #expect(try await cache.search("100%", at: now).map(\.id) == ["b"])
  }

  @Test
  func searchByTextNeverMatchesPrivateEvents() async throws {
    try await cache.replace([event("a", "Privat", at: 14, isPrivate: true)], from: hour(0), to: hour(24))
    #expect(try await cache.search("Privat", at: hour(12)).isEmpty)
    #expect(try await cache.search("", at: hour(12)).map(\.id) == ["a"])
  }

  // MARK: Private

  private let cache: CalendarEventCache

  private func hour(_ hour: Int64) -> Timestamp {
    Timestamp(milliseconds: 1_790_000_000_000 + hour * 3_600_000)
  }

  private func event(
    _ id: String,
    _ title: String,
    at start: Int64,
    series: String? = nil,
    attendees: Int = 0,
    online: Bool = false,
    isPrivate: Bool = false,
  ) -> CalendarEvent {
    CalendarEvent(
      id: id,
      seriesID: series,
      title: title,
      start: hour(start),
      end: hour(start + 1),
      attendeeCount: attendees,
      isOnlineMeeting: online,
      isPrivate: isPrivate,
    )
  }
}
