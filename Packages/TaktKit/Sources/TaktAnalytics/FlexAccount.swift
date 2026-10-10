import Foundation
import TaktCore

// MARK: - FlexAccount

/// The flex-time account (AZ-05): start balance + Σ (net − target) − Σ payouts (AZ-07) from the
/// start day through today. Computed from working days, absences and payouts at query time.
public struct FlexAccount: Sendable {

  // MARK: Lifecycle

  /// `startDay` is any time on the first day that counts; `startBalance` is the balance before it,
  /// e.g. carried over from last year.
  public init(plan: TargetPlan, startBalance: TimeInterval, startDay: Timestamp, calendar: Calendar = .current) {
    self.plan = plan
    self.startBalance = startBalance
    self.startDay = startDay.localDay(in: calendar).lowerBound
    self.calendar = calendar
  }

  // MARK: Public

  public var plan: TargetPlan
  public var startBalance: TimeInterval
  /// Local midnight of the first day that counts.
  public var startDay: Timestamp
  public var calendar: Calendar

  /// The calendar quarter that holds `time`, from local midnight to local midnight.
  public static func quarter(containing time: Timestamp, calendar: Calendar) -> Range<Timestamp> {
    let parts = calendar.dateComponents([.year, .month], from: time.date)
    let firstMonth = ((parts.month ?? 1) - 1) / 3 * 3 + 1
    guard
      let start = calendar.date(from: DateComponents(year: parts.year, month: firstMonth, day: 1)),
      let end = calendar.date(byAdding: .month, value: 3, to: start)
    else { return time.localDay(in: calendar) }
    return Timestamp(start)..<Timestamp(end)
  }

  /// Σ of the payouts whose day lies in `range`.
  public static func paidOut(_ payouts: [OvertimePayout], in range: Range<Timestamp>, calendar: Calendar) -> TimeInterval {
    let first = range.lowerBound.localDayString(in: calendar)
    let last = Timestamp(milliseconds: max(range.lowerBound.milliseconds, range.upperBound.milliseconds - 1))
      .localDayString(in: calendar)
    // `YYYY-MM-DD` sorts like the date.
    return payouts.filter { $0.day >= first && $0.day <= last }.reduce(0) { $0 + $1.seconds }
  }

  /// The balance at the end of `now`'s day, which counts with its full target. Days after it do
  /// not count yet. `days` are the working days from `WorkDay.days`; those before the start day
  /// are ignored, like payouts outside the start day through today. `plan.absences` must cover
  /// the days from the start day through today.
  public func balance(_ days: [WorkDay], payouts: [OvertimePayout] = [], now: Timestamp) -> TimeInterval {
    let end = now.localDay(in: calendar).upperBound
    let net = days.filter { $0.day >= startDay && $0.day < end }.reduce(0) { $0 + $1.net }
    var target: TimeInterval = 0
    var day = startDay
    while day < end {
      target += plan.target(on: day, calendar: calendar)
      guard let next = calendar.date(byAdding: .day, value: 1, to: day.date) else { break }
      day = Timestamp(next)
    }
    let paid = Self.paidOut(payouts, in: startDay..<end, calendar: calendar)
    return startBalance + net - target - paid
  }

  /// Overtime of a working day (AZ-07): net time beyond the day's target; on a day without a
  /// target (weekend, public holiday, absence) all of it.
  public func overtime(_ day: WorkDay) -> TimeInterval {
    max(0, day.net - plan.target(on: day.day, calendar: calendar))
  }

}

// MARK: - OvertimeQuota

/// AZ-07: paid-out overtime of a quarter against the optional quota. The quota limits only what is
/// paid out; overtime kept in the flex account has no limit. Exceeding it is a hint, no lock.
public struct OvertimeQuota: Hashable, Sendable {

  // MARK: Lifecycle

  public init(quota: TimeInterval, paid: TimeInterval) {
    self.quota = quota
    self.paid = paid
  }

  // MARK: Public

  public var quota: TimeInterval
  public var paid: TimeInterval

  /// Negative once more is paid out than the quota allows.
  public var remaining: TimeInterval {
    quota - paid
  }
}
