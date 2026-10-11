import Foundation
import Synchronization
import TaktCore
import TaktStore
import Testing

@testable import TaktCalendar

// MARK: - GraphCalendarClientTests

struct GraphCalendarClientTests {

  // MARK: Internal

  @Test
  func calendarViewAsksOnlyForTheNamedFields() throws {
    let url = try #require(GraphCalendarClient.calendarViewURL(from: monday, to: monday.adding(seconds: 86400)))
    let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    #expect(url.path == "/v1.0/me/calendarView")
    #expect(query["startDateTime"] == "2026-10-12T00:00:00Z")
    #expect(query["endDateTime"] == "2026-10-13T00:00:00Z")
    #expect(query["$select"]?.contains("body") == false)
    #expect(query["$select"]?.contains("attendees") == true)
  }

  @Test
  func eventsAreMappedWithUTCTimesAndCountedAttendees() async throws {
    let client = makeClient([page(events: [
      #"""
      {"id":"occ-1","subject":"Daily","start":{"dateTime":"2026-10-12T08:00:00.0000000","timeZone":"UTC"},
       "end":{"dateTime":"2026-10-12T08:15:00.0000000","timeZone":"UTC"},"seriesMasterId":"series-1",
       "attendees":[{"emailAddress":{"name":"A"}},{"emailAddress":{"name":"B"}}],"isOnlineMeeting":true,
       "sensitivity":"normal","isCancelled":false,"responseStatus":{"response":"accepted"}}
      """#
    ])])
    let events = try await client.events(from: monday, to: monday.adding(seconds: 86400))
    #expect(events == [
      CalendarEvent(
        id: "occ-1",
        seriesID: "series-1",
        title: "Daily",
        start: monday.adding(seconds: 8 * 3600),
        end: monday.adding(seconds: 8 * 3600 + 900),
        attendeeCount: 2,
        isOnlineMeeting: true,
        isPrivate: false,
      )
    ])
    let request = try #require(requests.list.withLock { $0.first })
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer graph-token")
    #expect(request.value(forHTTPHeaderField: "Prefer") == #"outlook.timezone="UTC""#)
  }

  @Test
  func cancelledDeclinedAndAllDayEventsAreLeftOut() async throws {
    let client = makeClient([page(events: [
      event(id: "cancelled", extra: #""isCancelled":true"#),
      event(id: "all-day", extra: #""isAllDay":true"#),
      event(id: "declined", extra: #""responseStatus":{"response":"declined"}"#),
      event(id: "kept", extra: #""responseStatus":{"response":"tentativelyAccepted"}"#),
    ])])
    #expect(try await client.events(from: monday, to: monday.adding(seconds: 86400)).map(\.id) == ["kept"])
  }

  @Test
  func privateEventsLoseTheirTitle() async throws {
    let client = makeClient([page(events: [event(id: "p", extra: #""sensitivity":"private""#)])])
    let event = try #require(try await client.events(from: monday, to: monday.adding(seconds: 86400)).first)
    #expect(event.isPrivate)
    #expect(event.title.isEmpty)
  }

  @Test
  func followsNextLinks() async throws {
    let client = makeClient([
      page(events: [event(id: "1")], next: "https://graph.microsoft.com/v1.0/me/calendarView?$skip=100"),
      page(events: [event(id: "2")]),
    ])
    #expect(try await client.events(from: monday, to: monday.adding(seconds: 86400)).map(\.id) == ["1", "2"])
    #expect(requests.list.withLock { $0.last?.url?.query?.contains("skip=100") } == true)
  }

  @Test
  func rejectedTokenIsUnauthorized() async throws {
    let client = makeClient([(status: 401, body: "{}")])
    await #expect(throws: GraphCalendarError.unauthorized) {
      try await client.events(from: monday, to: monday.adding(seconds: 86400))
    }
  }

  @Test
  func syncReplacesTheCacheForTodayPlusMinusSevenDays() async throws {
    let cache = try CalendarEventCache(database: AppDatabase.inMemory())
    let clock = ManualClock(monday.adding(seconds: 10 * 3600))
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let sync = CalendarSync(client: makeClient([page(events: [event(id: "1")])]), cache: cache, clock: clock, calendar: calendar)
    try await sync.sync()
    let window = await sync.window()
    #expect(window.start == monday.adding(seconds: -7 * 86400))
    #expect(window.end == monday.adding(seconds: 8 * 86400))
    #expect(try await cache.events(from: window.start, to: window.end).map(\.id) == ["1"])
    let url = try #require(requests.list.withLock { $0.first?.url?.absoluteString })
    #expect(url.contains("startDateTime=2026-10-05T00:00:00Z"))
  }

  // MARK: Private

  private final class Requests: Sendable {
    let list = Mutex<[URLRequest]>([])
  }

  /// Monday, 12 October 2026, 00:00 UTC.
  private let monday = Timestamp(milliseconds: 1_791_763_200_000)
  private let requests = Requests()

  private func makeClient(_ responses: [(status: Int, body: String)]) -> GraphCalendarClient {
    let queue = Mutex(responses)
    return GraphCalendarClient(token: { "graph-token" }) { [requests] request in
      requests.list.withLock { $0.append(request) }
      let next = queue.withLock { $0.isEmpty ? (status: 500, body: "{}") : $0.removeFirst() }
      let url = try #require(request.url)
      let response = try #require(
        HTTPURLResponse(url: url, statusCode: next.status, httpVersion: nil, headerFields: nil)
      )
      return (Data(next.body.utf8), response)
    }
  }

  private func page(events: [String], next: String? = nil) -> (status: Int, body: String) {
    let link = next.map { #","@odata.nextLink":"\#($0)""# } ?? ""
    return (200, #"{"value":[\#(events.joined(separator: ","))]\#(link)}"#)
  }

  private func event(id: String, extra: String = #""sensitivity":"normal""#) -> String {
    #"""
    {"id":"\#(id)","subject":"Termin \#(id)","start":{"dateTime":"2026-10-12T09:00:00.0000000","timeZone":"UTC"},
     "end":{"dateTime":"2026-10-12T10:00:00.0000000","timeZone":"UTC"},\#(extra)}
    """#
  }
}
