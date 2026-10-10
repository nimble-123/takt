import Foundation
import TaktCore
import Testing

@testable import TaktAnalytics

// MARK: - FlexAccountTests

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

// MARK: - Overtime and payouts (AZ-07)

extension FlexAccountTests {
  @Test
  func overtimeIsNetBeyondTheTargetAndAllOfItWithoutATarget() throws {
    var plan = TargetPlan(weeklyHours: 40, federalState: .hesse)
    plan.absences = ["2026-10-06": .vacation]
    let account = FlexAccount(plan: plan, startBalance: 0, startDay: try day(2026, 10, 1), calendar: calendar)

    // Monday 10 h, vacation on Tuesday with 2 h, Saturday 3 October (holiday) 4 h, Wednesday 6 h.
    #expect(account.overtime(try work(day(2026, 10, 5), hours: 10)) == 2 * 3600)
    #expect(account.overtime(try work(day(2026, 10, 6), hours: 2)) == 2 * 3600)
    #expect(account.overtime(try work(day(2026, 10, 3), hours: 4)) == 4 * 3600)
    #expect(account.overtime(try work(day(2026, 10, 7), hours: 6)) == 0)
  }

  @Test
  func payoutsReduceTheBalanceAndMayMakeItNegative() throws {
    let account = FlexAccount(
      plan: TargetPlan(weeklyHours: 40),
      startBalance: 5 * 3600,
      startDay: try day(2026, 10, 5),
      calendar: calendar,
    )
    let days = try [work(day(2026, 10, 5), hours: 8)]
    let created = try day(2026, 10, 1)
    let payouts = [
      OvertimePayout(day: "2026-10-04", seconds: 3600, createdAt: created), // before the start day
      OvertimePayout(day: "2026-10-05", seconds: 8 * 3600, createdAt: created),
      OvertimePayout(day: "2026-10-09", seconds: 3600, createdAt: created), // after today
    ]

    #expect(account.balance(days, payouts: payouts, now: try day(2026, 10, 5).adding(seconds: 20 * 3600)) == -3 * 3600)
  }

  @Test
  func quartersAndPayoutsAcrossTheirBoundary() throws {
    let quarter = FlexAccount.quarter(containing: try day(2026, 11, 15), calendar: calendar)
    #expect(quarter == (try day(2026, 10, 1))..<(try day(2027, 1, 1)))

    let created = try day(2026, 9, 1)
    let payouts = [
      OvertimePayout(day: "2026-09-30", seconds: 3600, createdAt: created),
      OvertimePayout(day: "2026-10-01", seconds: 2 * 3600, createdAt: created),
      OvertimePayout(day: "2026-12-31", seconds: 4 * 3600, createdAt: created),
    ]
    #expect(FlexAccount.paidOut(payouts, in: quarter, calendar: calendar) == 6 * 3600)
    #expect(OvertimeQuota(quota: 5 * 3600, paid: 6 * 3600).remaining == -3600)
  }
}

// MARK: - Carryover limit (AZ-08)

extension FlexAccountTests {

  // MARK: Internal

  @Test(arguments: [(12.0, 10.0, 2.0), (10.0, 10.0, 0.0), (8.0, 8.0, 0.0)])
  func positiveBalanceIsCappedAtTheYearChange(hours: Double, balance: Double, forfeited: Double) throws {
    let account = capped(startBalance: 0, startDay: try day(2025, 12, 1))
    let days = try [work(day(2025, 12, 1), hours: hours)]
    let now = try day(2026, 1, 5)

    #expect(account.balance(days, now: now) == balance * 3600)
    #expect(account.forfeitures(days, now: now)[2025, default: 0] == forfeited * 3600)
  }

  @Test
  func negativeBalanceAndNoLimitAreNotCapped() throws {
    let now = try day(2026, 1, 5)
    #expect(capped(startBalance: -5 * 3600, startDay: try day(2025, 12, 1)).balance([], now: now) == -5 * 3600)

    var account = capped(startBalance: 0, startDay: try day(2025, 12, 1))
    account.carryoverLimit = nil
    #expect(account.balance(try [work(day(2025, 12, 1), hours: 12)], now: now) == 12 * 3600)
  }

  @Test
  func everyYearIsCappedOnItsOwnAndNotBeforeItEnds() throws {
    let account = capped(startBalance: 0, startDay: try day(2024, 12, 1))
    let days = try [work(day(2024, 12, 2), hours: 12), work(day(2025, 12, 1), hours: 12)]

    #expect(account.balance(days, now: try day(2026, 1, 1)) == 10 * 3600)
    #expect(account.forfeitures(days, now: try day(2026, 1, 1)) == [2024: 2 * 3600, 2025: 12 * 3600])
    // On 31 December the year has not ended yet.
    #expect(account.balance(days, now: try day(2025, 12, 31)) == 22 * 3600)
  }

  @Test
  func startBalanceIsTheCarryoverAndNotCappedItself() throws {
    let account = capped(startBalance: 300 * 3600, startDay: try day(2026, 1, 1))

    #expect(account.balance([], now: try day(2026, 1, 5)) == 300 * 3600)
  }

  // MARK: Private

  private func capped(startBalance: TimeInterval, startDay: Timestamp) -> FlexAccount {
    // No target, so only the work counts.
    FlexAccount(
      plan: TargetPlan(weeklyHours: 0),
      startBalance: startBalance,
      startDay: startDay,
      carryoverLimit: 10 * 3600,
      calendar: calendar,
    )
  }
}
