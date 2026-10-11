// MARK: - EventStartCheck

/// Finds events whose series asks for a timer at the start and whose start has just passed,
/// each once (CA-21). Called about once a minute.
public struct EventStartCheck: Sendable {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  /// Events that began since the last check (on the first check: within the last minute).
  public mutating func check(_ events: [CalendarEvent], rules: [String: SeriesRule], now: Timestamp) -> [CalendarEvent] {
    let since = last ?? now.adding(seconds: -60)
    last = now
    let due = events.filter { event in
      guard let series = event.seriesID, rules[series]?.offersTimerAtStart == true else { return false }
      return event.start > since && event.start <= now && !announced.contains(event.id)
    }
    announced.formUnion(due.map(\.id))
    return due
  }

  // MARK: Private

  private var last: Timestamp?
  private var announced = Set<String>()
}
