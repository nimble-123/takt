import Foundation
import os
import TaktCore

// MARK: - GraphCalendarError

public enum GraphCalendarError: Error, Equatable {
  /// The token was rejected; the user has to sign in again.
  case unauthorized
  case throttled(retryAfter: Int?)
  case http(Int)
}

// MARK: - GraphCalendarClient

/// Reads the signed-in user's own calendar through Microsoft Graph, read-only (CA-02). Only the
/// fields CA-04 names are requested; attendees are counted and then dropped.
public struct GraphCalendarClient: Sendable {

  // MARK: Lifecycle

  public init(
    token: @escaping TokenProvider,
    transport: @escaping Transport = { try await URLSession.shared.data(for: $0) },
  ) {
    self.token = token
    self.transport = transport
  }

  // MARK: Public

  /// A valid Graph access token with `Calendars.Read`.
  public typealias TokenProvider = @Sendable () async throws -> String
  /// Sends a request and returns the body and response, like `URLSession.data(for:)`.
  public typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

  /// Occurrences overlapping `start..<end`, recurring events expanded by Graph. Cancelled and
  /// declined events are left out (CA-14), and so are all-day events: nobody times a holiday.
  public func events(from start: Timestamp, to end: Timestamp) async throws -> [CalendarEvent] {
    var next: URL? = Self.calendarViewURL(from: start, to: end)
    var events = [CalendarEvent]()
    while let url = next {
      let page: Page = try await get(url)
      events += page.value.compactMap(\.calendarEvent)
      next = page.nextLink
    }
    return events
  }

  // MARK: Internal

  static func calendarViewURL(from start: Timestamp, to end: Timestamp) -> URL? {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "graph.microsoft.com"
    components.path = "/v1.0/me/calendarView"
    components.queryItems = [
      URLQueryItem(name: "startDateTime", value: Self.isoString(start)),
      URLQueryItem(name: "endDateTime", value: Self.isoString(end)),
      URLQueryItem(
        name: "$select",
        value: "subject,start,end,isAllDay,seriesMasterId,attendees,isOnlineMeeting,sensitivity,isCancelled,responseStatus",
      ),
      URLQueryItem(name: "$orderby", value: "start/dateTime"),
      URLQueryItem(name: "$top", value: "100"),
    ]
    return components.url
  }

  // MARK: Private

  private struct Page: Decodable {
    enum CodingKeys: String, CodingKey {
      case value
      case nextLink = "@odata.nextLink"
    }

    var value: [GraphEvent]
    var nextLink: URL?
  }

  private struct GraphEvent: Decodable {
    struct DateTimeZone: Decodable {
      var dateTime: String
    }

    struct ResponseStatus: Decodable {
      var response: String?
    }

    struct Attendee: Decodable { }

    var id: String
    var subject: String?
    var start: DateTimeZone
    var end: DateTimeZone
    var isAllDay: Bool?
    var seriesMasterId: String?
    var attendees: [Attendee]?
    var isOnlineMeeting: Bool?
    var sensitivity: String?
    var isCancelled: Bool?
    var responseStatus: ResponseStatus?

    var calendarEvent: CalendarEvent? {
      guard
        isCancelled != true, isAllDay != true, responseStatus?.response != "declined",
        let start = GraphCalendarClient.timestamp(start.dateTime),
        let end = GraphCalendarClient.timestamp(end.dateTime)
      else { return nil }
      let isPrivate = sensitivity == "private" || sensitivity == "confidential"
      return CalendarEvent(
        id: id,
        seriesID: seriesMasterId,
        title: isPrivate ? "" : subject ?? "",
        start: start,
        end: end,
        attendeeCount: attendees?.count ?? 0,
        isOnlineMeeting: isOnlineMeeting ?? false,
        isPrivate: isPrivate,
      )
    }
  }

  private let token: TokenProvider
  private let transport: Transport
  private let logger = Logger(subsystem: "de.nilslutz.takt", category: "calendar")

  /// `2026-10-12T08:00:00Z`; Graph accepts it for `startDateTime` and `endDateTime`.
  private static func isoString(_ timestamp: Timestamp) -> String {
    timestamp.date.formatted(.iso8601)
  }

  /// Graph's `dateTime` in UTC (asked for with `Prefer: outlook.timezone="UTC"`) has seven
  /// fractional digits and no zone; whole seconds are enough here.
  private static func timestamp(_ value: String) -> Timestamp? {
    let seconds = String(value.prefix(19)) + "Z"
    return (try? Date(seconds, strategy: .iso8601)).map(Timestamp.init)
  }

  private func get<Value: Decodable>(_ url: URL) async throws -> Value {
    var request = URLRequest(url: url, timeoutInterval: 20)
    request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
    request.setValue("outlook.timezone=\"UTC\"", forHTTPHeaderField: "Prefer")
    let (data, response) = try await transport(request)
    let http = response as? HTTPURLResponse
    switch http?.statusCode ?? 0 {
    case 200..<300:
      return try JSONDecoder().decode(Value.self, from: data)
    case 401, 403:
      throw GraphCalendarError.unauthorized
    case 429:
      throw GraphCalendarError.throttled(retryAfter: http?.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
    case let status:
      logger.error("Graph calendar request failed with status \(status, privacy: .public)")
      throw GraphCalendarError.http(status)
    }
  }
}
