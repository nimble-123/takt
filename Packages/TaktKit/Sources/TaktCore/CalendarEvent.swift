// MARK: - CalendarEvent

/// One occurrence of an Outlook event, cached for the start search (CA-04, CA-05). Only the fields
/// the PRD names are kept; the title of a private event is never stored.
public struct CalendarEvent: Hashable, Sendable, Identifiable {

  // MARK: Lifecycle

  public init(
    id: String,
    seriesID: String?,
    title: String,
    start: Timestamp,
    end: Timestamp,
    attendeeCount: Int,
    isOnlineMeeting: Bool,
    isPrivate: Bool,
  ) {
    self.id = id
    self.seriesID = seriesID
    self.title = title
    self.start = start
    self.end = end
    self.attendeeCount = attendeeCount
    self.isOnlineMeeting = isOnlineMeeting
    self.isPrivate = isPrivate
  }

  // MARK: Public

  /// The Graph ID of this occurrence.
  public var id: String
  /// The series master's ID for recurring events (CA-20), nil for single events.
  public var seriesID: String?
  /// Empty for private events; the UI shows "Privat" instead.
  public var title: String
  public var start: Timestamp
  public var end: Timestamp
  public var attendeeCount: Int
  public var isOnlineMeeting: Bool
  public var isPrivate: Bool

  /// Events that began before `now` and for which `segments` cover less than half of the time
  /// up to now, so the day view can offer them (CA-23).
  public static func untracked(_ events: [CalendarEvent], segments: [Segment], now: Timestamp) -> [CalendarEvent] {
    events.filter { event in
      guard event.start < now else { return false }
      let end = min(event.end, now)
      let length = end.milliseconds - event.start.milliseconds
      let covered = segments.reduce(Int64(0)) { sum, segment in
        let overlap = min(segment.end ?? now, end).milliseconds - max(segment.start, event.start).milliseconds
        return sum + max(0, overlap)
      }
      return covered * 2 < length
    }
  }

  /// Running at `now`, or starting within `lead` seconds (CA-11).
  public func isCurrent(at now: Timestamp, lead seconds: Int64 = 15 * 60) -> Bool {
    start.milliseconds - seconds * 1000 <= now.milliseconds && now < end
  }
}
