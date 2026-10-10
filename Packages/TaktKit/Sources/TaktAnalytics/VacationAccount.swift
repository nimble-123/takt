import Foundation
import TaktCore

/// The vacation account in whole days (AZ-06): carryover + entitlement − taken − planned. Computed
/// from the vacation markers at query time; only the first year's carryover is a setting, later
/// years carry over what is left.
public struct VacationAccount: Sendable {

  // MARK: Lifecycle

  /// `carryover` is what is left from the year before `startYear`.
  public init(plan: TargetPlan, daysPerYear: Int, carryover: Int, startYear: Int, calendar: Calendar = .current) {
    self.plan = plan
    self.daysPerYear = daysPerYear
    self.carryover = carryover
    self.startYear = startYear
    self.calendar = calendar
  }

  // MARK: Public

  public struct Year: Hashable, Sendable {
    public var year: Int
    /// Left from the year before; may be negative when more was taken than available.
    public var carryover: Int
    public var entitlement: Int
    /// Vacation days through today.
    public var taken: Int
    /// Vacation days after today.
    public var planned: Int
    /// Carryover not used by 31 March (§ 7 para. 3 BUrlG); vacation until then uses the carryover
    /// first, planned days included. Only a hint, nothing expires.
    public var carryoverOpen: Int

    public var available: Int {
      carryover + entitlement
    }

    public var left: Int {
      available - taken - planned
    }
  }

  public var plan: TargetPlan
  public var daysPerYear: Int
  public var carryover: Int
  public var startYear: Int
  public var calendar: Calendar

  /// Vacation days in `range` that count, for the working time record.
  public func days(in range: Range<Timestamp>, absences: [String: AbsenceKind]) -> Int {
    var count = 0
    var day = range.lowerBound.localDay(in: calendar).lowerBound
    while day < range.upperBound {
      if absences[day.localDayString(in: calendar)] == .vacation, plan.isWorkingDay(day, calendar: calendar) {
        count += 1
      }
      guard let next = calendar.date(byAdding: .day, value: 1, to: day.date) else { break }
      day = Timestamp(next)
    }
    return count
  }

  /// The account of `year` as of `now`. `absences` must cover 1 January of `startYear` through
  /// 31 December of `year`; only vacation on working days without a public holiday counts.
  public func year(_ year: Int, absences: [String: AbsenceKind], now: Timestamp) -> Year {
    let today = now.localDayString(in: calendar)
    var days = [Int: (taken: Int, planned: Int, untilMarch: Int)]()
    for (date, kind) in absences where kind == .vacation {
      guard
        let parts = Timestamp.localDayParts(date),
        let start = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)),
        plan.isWorkingDay(Timestamp(start), calendar: calendar)
      else { continue }
      var count = days[parts.year] ?? (0, 0, 0)
      // `YYYY-MM-DD` sorts like the date.
      if date <= today { count.taken += 1 } else { count.planned += 1 }
      if parts.month <= 3 { count.untilMarch += 1 }
      days[parts.year] = count
    }
    var carry = year < startYear ? 0 : carryover
    var result = Year(year: year, carryover: carry, entitlement: daysPerYear, taken: 0, planned: 0, carryoverOpen: 0)
    for current in min(startYear, year)...year {
      let count = days[current] ?? (0, 0, 0)
      result = Year(
        year: current,
        carryover: carry,
        entitlement: daysPerYear,
        taken: count.taken,
        planned: count.planned,
        carryoverOpen: max(0, carry - count.untilMarch),
      )
      carry = result.left
    }
    return result
  }
}
