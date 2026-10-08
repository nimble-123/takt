import Foundation
import TaktCore

/// Target working time against tracked time (AN-07, "Soll/Ist gegen Wochenstunden").
public struct TargetPlan: Hashable, Sendable {

  // MARK: Lifecycle

  public init(weeklyHours: Double = 40, workDays: Set<Int> = [1, 2, 3, 4, 5]) {
    self.weeklyHours = max(0, weeklyHours)
    self.workDays = workDays.filter { (1...7).contains($0) }
  }

  // MARK: Public

  public struct Comparison: Hashable, Sendable {
    public var target: TimeInterval
    public var actual: TimeInterval

    /// Actual − target; negative means hours are missing.
    public var balance: TimeInterval {
      actual - target
    }
  }

  /// Contractual hours per week.
  public private(set) var weeklyHours: Double
  /// Working days, 1 = Monday … 7 = Sunday.
  public private(set) var workDays: Set<Int>

  /// Target seconds of a local day: the weekly hours spread evenly over the working days.
  public func target(on day: Timestamp, calendar: Calendar) -> TimeInterval {
    guard !workDays.isEmpty, workDays.contains(day.mondayBasedWeekday(in: calendar)) else { return 0 }
    return weeklyHours * 3600 / Double(workDays.count)
  }

  /// Target and tracked time of the report's days up to and including `now`'s day; later days
  /// have no target yet, so the middle of a week does not show missing hours.
  public func compare(_ report: Report, now: Timestamp, calendar: Calendar) -> Comparison {
    let today = now.localDay(in: calendar)
    var comparison = Comparison(target: 0, actual: 0)
    for day in report.days where day.start < today.upperBound {
      comparison.target += target(on: day.start, calendar: calendar)
    }
    // Allocated time, so parallel time counts as the user chose.
    comparison.actual = report.slices.filter { $0.day < today.upperBound }.reduce(0) { $0 + $1.seconds }
    return comparison
  }

}
