import Foundation

// MARK: - CoreHours

/// The usual working hours on working days (#246): the timelines shade the time outside them, and
/// the reminder without a timer only runs inside them (TM-09).
public struct CoreHours: Hashable, Sendable {

  // MARK: Lifecycle

  /// Minutes after local midnight; `workDays` 1 = Monday … 7 = Sunday.
  public init(startMinute: Int = 6 * 60, endMinute: Int = 19 * 60, workDays: Set<Int> = [1, 2, 3, 4, 5]) {
    self.startMinute = startMinute
    self.endMinute = endMinute
    self.workDays = workDays
  }

  // MARK: Public

  public var startMinute: Int
  public var endMinute: Int
  public var workDays: Set<Int>

  /// The parts of the local day `day` outside the core hours; the whole day on a day off or a
  /// public holiday. Wall-clock times, so a day with a daylight saving change keeps 6:00–19:00.
  public func offHours(in day: Range<Timestamp>, isHoliday: Bool, calendar: Calendar) -> [Range<Timestamp>] {
    guard
      !isHoliday,
      workDays.contains(day.lowerBound.mondayBasedWeekday(in: calendar)),
      startMinute < endMinute
    else { return [day] }
    let start = time(startMinute, on: day, calendar: calendar)
    let end = time(endMinute, on: day, calendar: calendar)
    return [day.lowerBound..<start, end..<day.upperBound].filter { !$0.isEmpty }
  }

  // MARK: Private

  private func time(_ minute: Int, on day: Range<Timestamp>, calendar: Calendar) -> Timestamp {
    let date = calendar.date(
      bySettingHour: minute / 60,
      minute: minute % 60,
      second: 0,
      of: day.lowerBound.date,
    )
    return date.map { min(max(Timestamp($0), day.lowerBound), day.upperBound) } ?? day.lowerBound
  }
}
