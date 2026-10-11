import TaktCore

// MARK: - CalendarEvents

/// Outlook events for the start search (CA-10–CA-14); set by the app when a Microsoft account
/// is configured.
nonisolated public struct CalendarEvents: Sendable {

  // MARK: Lifecycle

  public init(
    search: @escaping @Sendable (String, Timestamp) async throws -> [CalendarEvent],
    refresh: @escaping @Sendable () async -> Void,
  ) {
    self.search = search
    self.refresh = refresh
  }

  // MARK: Public

  /// Cached events not yet over whose title contains the text (all of them for empty text).
  public var search: @Sendable (String, Timestamp) async throws -> [CalendarEvent]
  /// Fetches the calendar again, e.g. when the popover opens (CA-05).
  public var refresh: @Sendable () async -> Void

  // MARK: Internal

  /// How far back a timer started from an event may begin at the event's start (CA-13).
  static let backdateLimit: Int64 = 10 * 60_000

  /// Where a timer for `event` starts: at the event's start if that was up to ten minutes ago,
  /// otherwise now (CA-13).
  static func start(for event: CalendarEvent, at now: Timestamp) -> Timestamp? {
    let elapsed = now.milliseconds - event.start.milliseconds
    return elapsed > 0 && elapsed <= backdateLimit ? event.start : nil
  }
}
