import Foundation
import TaktCore

/// The month close (AZ-10): which month to archive and which working days lack a record. Computed
/// at query time; the archive itself is a folder of files.
public enum MonthClose {

  /// A working day must be recorded within this many days (§ 17 para. 1 MiLoG).
  public static let recordingDays = 7

  /// The calendar month before the one of `now`.
  public static func previousMonth(of now: Timestamp, calendar: Calendar) -> Range<Timestamp>? {
    guard
      let month = calendar.dateInterval(of: .month, for: now.date),
      let previous = calendar.date(byAdding: .month, value: -1, to: month.start)
    else { return nil }
    return Timestamp(previous)..<Timestamp(month.start)
  }

  /// `YYYY-MM` of the month that starts at `start`, e.g. for file names.
  public static func monthString(_ start: Timestamp, calendar: Calendar) -> String {
    String(start.localDayString(in: calendar).prefix(7))
  }

  /// Working days from `start` on that are more than `recordingDays` old and have neither working
  /// time in `days` nor an absence in `plan`. Weekends and public holidays are no working days.
  public static func openDays(
    from start: Timestamp,
    days: [WorkDay],
    plan: TargetPlan,
    now: Timestamp,
    calendar: Calendar,
  ) -> [Timestamp] {
    guard
      let end = calendar.date(byAdding: .day, value: -recordingDays, to: now.localDay(in: calendar).lowerBound.date)
    else { return [] }
    let recorded = Set(days.map { $0.day.localDayString(in: calendar) })
    var open = [Timestamp]()
    var day = start.localDay(in: calendar).lowerBound
    while day < Timestamp(end) {
      let key = day.localDayString(in: calendar)
      if plan.isWorkingDay(day, calendar: calendar), !recorded.contains(key), plan.absences[key] == nil {
        open.append(day)
      }
      guard let next = calendar.date(byAdding: .day, value: 1, to: day.date) else { break }
      day = Timestamp(next)
    }
    return open
  }
}
