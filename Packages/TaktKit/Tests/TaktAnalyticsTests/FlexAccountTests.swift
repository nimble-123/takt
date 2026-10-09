import Foundation
import TaktCore
import Testing

@testable import TaktAnalytics

struct FlexAccountTests {

  // MARK: Lifecycle

  init() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
  }

  // MARK: Internal

  @Test
  func balanceRunsOverAMonthBoundary() throws {
    // Monday 28 September to Friday 2 October 2026, 9 hours each: +1 h per day.
    let start = try day(2026, 9, 28)
    let days = try (0..<5).map { try work(day(2026, 9, 28 + $0), hours: 9) }
    let account = FlexAccount(plan: TargetPlan(weeklyHours: 40), startBalance: 0, startDay: start, calendar: calendar)

    #expect(account.balance(days, now: try day(2026, 10, 2).adding(seconds: 20 * 3600)) == 5 * 3600)
    // The weekend has no target, Monday 5 October counts in full while it runs.
    #expect(account.balance(days, now: try day(2026, 10, 5).adding(seconds: 9 * 3600)) == -3 * 3600)
  }

  @Test
  func absencesAndHolidaysHaveNoTarget() throws {
    var plan = TargetPlan(weeklyHours: 40, federalState: .hesse)
    // Thursday 1 October vacation, Friday 2 October nothing, Saturday 3 October German Unity Day.
    plan.absences = ["2026-10-01": .vacation]
    let account = FlexAccount(plan: plan, startBalance: 0, startDay: try day(2026, 10, 1), calendar: calendar)

    #expect(account.balance([], now: try day(2026, 10, 4)) == -8 * 3600)
  }

  @Test
  func negativeStartBalanceAndTheStartDay() throws {
    let account = FlexAccount(
      plan: TargetPlan(weeklyHours: 40),
      startBalance: -10 * 3600,
      startDay: try day(2026, 10, 6),
      calendar: calendar,
    )
    // Work before the start day is in the start balance already.
    let days = try [work(day(2026, 10, 5), hours: 12), work(day(2026, 10, 6), hours: 10)]

    #expect(account.balance(days, now: try day(2026, 10, 6).adding(seconds: 18 * 3600)) == -8 * 3600)
  }

  @Test
  func daysInTheFutureDoNotCount() throws {
    let account = FlexAccount(
      plan: TargetPlan(weeklyHours: 40),
      startBalance: 0,
      startDay: try day(2026, 10, 5),
      calendar: calendar,
    )
    let days = try [work(day(2026, 10, 5), hours: 8), work(day(2026, 10, 7), hours: 8)]

    #expect(account.balance(days, now: try day(2026, 10, 5).adding(seconds: 18 * 3600)) == 0)
  }

  // MARK: Private

  private let calendar: Calendar

  private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Timestamp {
    Timestamp(try #require(calendar.date(from: DateComponents(year: year, month: month, day: day))))
  }

  private func work(_ day: Timestamp, hours: Double) -> WorkDay {
    let start = day.adding(seconds: 8 * 3600)
    return WorkDay(
      day: day,
      start: start,
      end: start.adding(seconds: hours * 3600),
      breaks: [],
      shortInterruptions: 0,
      net: hours * 3600,
    )
  }
}
