import Foundation
import TaktCore
import TaktStore

// MARK: - CalendarSync

/// Fetches today ± 7 days from Outlook into the local cache (CA-05). The app calls it every five
/// minutes and whenever the popover opens; overlapping calls share one request.
public actor CalendarSync {

  // MARK: Lifecycle

  public init(
    client: GraphCalendarClient,
    cache: CalendarEventCache,
    clock: any TaktClock,
    calendar: Calendar = .current,
  ) {
    self.client = client
    self.cache = cache
    self.clock = clock
    self.calendar = calendar
  }

  // MARK: Public

  /// Replaces the cached window with what Graph returns now.
  public func sync() async throws {
    if let running {
      return try await running.value
    }
    let task = Task { try await fetch() }
    running = task
    defer { running = nil }
    try await task.value
  }

  // MARK: Internal

  /// From midnight seven days ago to midnight eight days ahead, in the user's time zone.
  func window() -> (start: Timestamp, end: Timestamp) {
    let today = calendar.startOfDay(for: clock.now().date)
    let start = calendar.date(byAdding: .day, value: -7, to: today) ?? today
    let end = calendar.date(byAdding: .day, value: 8, to: today) ?? today
    return (Timestamp(start), Timestamp(end))
  }

  // MARK: Private

  private let client: GraphCalendarClient
  private let cache: CalendarEventCache
  private let clock: any TaktClock
  private let calendar: Calendar
  private var running: Task<Void, any Error>?

  private func fetch() async throws {
    let (start, end) = window()
    let events = try await client.events(from: start, to: end)
    try await cache.replace(events, from: start, to: end)
  }
}
