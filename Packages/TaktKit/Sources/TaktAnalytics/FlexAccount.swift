import Foundation
import TaktCore

// MARK: - FlexAccount

/// The flex-time account (AZ-05): start balance + Σ (net − target) − Σ payouts (AZ-07) from the
/// start day through today, capped at each year change (AZ-08). Computed from working days,
/// absences and payouts at query time.
public struct FlexAccount: Sendable {

  // MARK: Lifecycle

  /// `startDay` is any time on the first day that counts; `startBalance` is the balance before it,
  /// e.g. carried over from last year, so it is not capped itself.
  public init(
    plan: TargetPlan,
    startBalance: TimeInterval,
    startDay: Timestamp,
    carryoverLimit: TimeInterval? = nil,
    calendar: Calendar = .current,
  ) {
    self.plan = plan
    self.startBalance = startBalance
    self.startDay = startDay.localDay(in: calendar).lowerBound
    self.carryoverLimit = carryoverLimit
    self.calendar = calendar
  }

  // MARK: Public

  public var plan: TargetPlan
  public var startBalance: TimeInterval
  /// Local midnight of the first day that counts.
  public var startDay: Timestamp
  /// AZ-08: at most this positive balance carries over into a new year; `nil` = no limit.
  public var carryoverLimit: TimeInterval?
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
    ledger(days, payouts: payouts, now: now).balance
  }

  /// AZ-08: the hours forfeited at each year change from the start day through `now`, by the year
  /// that ended. Only a positive balance above the limit forfeits; nothing is stored.
  public func forfeitures(_ days: [WorkDay], payouts: [OvertimePayout] = [], now: Timestamp) -> [Int: TimeInterval] {
    ledger(days, payouts: payouts, now: now).forfeited
  }

  /// Overtime of a working day (AZ-07): net time beyond the day's target; on a day without a
  /// target (weekend, public holiday, absence) all of it.
  public func overtime(_ day: WorkDay) -> TimeInterval {
    max(0, day.net - plan.target(on: day.day, calendar: calendar))
  }

  // MARK: Private

  /// Year by year from the start day through `now`'s day; the limit applies when a year ends and
  /// a day of the next one counts.
  private func ledger(
    _ days: [WorkDay],
    payouts: [OvertimePayout],
    now: Timestamp,
  ) -> (balance: TimeInterval, forfeited: [Int: TimeInterval]) {
    let end = now.localDay(in: calendar).upperBound
    var balance = startBalance
    var forfeited = [Int: TimeInterval]()
    var from = startDay
    while from < end {
      let year = calendar.component(.year, from: from.date)
      let nextYear = calendar.date(from: DateComponents(year: year + 1, month: 1, day: 1)).map(Timestamp.init) ?? end
      let to = min(nextYear, end)
      balance += change(days, payouts: payouts, in: from..<to)
      if to < end, let carryoverLimit, balance > carryoverLimit {
        forfeited[year] = balance - carryoverLimit
        balance = carryoverLimit
      }
      from = to
    }
    return (balance, forfeited)
  }

  /// Net − target − payouts of the days in `range`.
  private func change(_ days: [WorkDay], payouts: [OvertimePayout], in range: Range<Timestamp>) -> TimeInterval {
    let net = days.filter { range.contains($0.day) }.reduce(0) { $0 + $1.net }
    var target: TimeInterval = 0
    var day = range.lowerBound
    while day < range.upperBound {
      target += plan.target(on: day, calendar: calendar)
      guard let next = calendar.date(byAdding: .day, value: 1, to: day.date) else { break }
      day = Timestamp(next)
    }
    return net - target - Self.paidOut(payouts, in: range, calendar: calendar)
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
