import Foundation
import TaktCore

/// The flex-time account (AZ-05): start balance + Σ (net − target) from the start day through
/// today. Computed from working days and absences at query time; nothing is stored.
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

  /// The balance at the end of `now`'s day, which counts with its full target. Days after it do
  /// not count yet. `days` are the working days from `WorkDay.days`; those before the start day
  /// are ignored. `plan.absences` must cover the days from the start day through today.
  public func balance(_ days: [WorkDay], now: Timestamp) -> TimeInterval {
    let end = now.localDay(in: calendar).upperBound
    let net = days.filter { $0.day >= startDay && $0.day < end }.reduce(0) { $0 + $1.net }
    var target: TimeInterval = 0
    var day = startDay
    while day < end {
      target += plan.target(on: day, calendar: calendar)
      guard let next = calendar.date(byAdding: .day, value: 1, to: day.date) else { break }
      day = Timestamp(next)
    }
    return startBalance + net - target
  }
}
