import Foundation
import TaktCore
import Testing

@testable import TaktAnalytics

struct MonthCloseTests {

  // MARK: Lifecycle

  init() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
  }

  // MARK: Internal

  @Test
  func previousMonthIsTheCalendarMonthBefore() throws {
    let october = try #require(MonthClose.previousMonth(of: try day(2026, 10, 10).adding(seconds: 3600), calendar: calendar))
    #expect(october == (try day(2026, 9, 1))..<(try day(2026, 10, 1)))
    #expect(MonthClose.monthString(october.lowerBound, calendar: calendar) == "2026-09")

    let january = try #require(MonthClose.previousMonth(of: try day(2027, 1, 1), calendar: calendar))
    #expect(january == (try day(2026, 12, 1))..<(try day(2027, 1, 1)))
  }

  @Test
  func workingDaysWithoutTimeOrAbsenceAreOpenAfterSevenDays() throws {
    var plan = TargetPlan(weeklyHours: 40, federalState: .hesse)
    plan.absences = ["2026-09-29": .vacation]
    let days = [work(try day(2026, 9, 28))]

    // Saturday 10 October: Friday 2 October is eight days old, Saturday 3 October no working day.
    let open = MonthClose.openDays(
      from: try day(2026, 9, 28),
      days: days,
      plan: plan,
      now: try day(2026, 10, 10).adding(seconds: 12 * 3600),
      calendar: calendar,
    )
    #expect(open == [try day(2026, 9, 30), try day(2026, 10, 1), try day(2026, 10, 2)])

    // A day later Friday 2 October is only seven days old.
    let earlier = MonthClose.openDays(
      from: try day(2026, 9, 28),
      days: days,
      plan: plan,
      now: try day(2026, 10, 9).adding(seconds: 23 * 3600),
      calendar: calendar,
    )
    #expect(earlier == [try day(2026, 9, 30), try day(2026, 10, 1)])
  }

  @Test
  func publicHolidaysAndDaysOffAreNotOpen() throws {
    // Corpus Christi on Thursday 4 June 2026 in Hesse; Friday 5 June not a working day.
    let plan = TargetPlan(weeklyHours: 32, workDays: [1, 2, 3, 4], federalState: .hesse)

    let open = MonthClose.openDays(from: try day(2026, 6, 1), days: [], plan: plan, now: try day(2026, 6, 15), calendar: calendar)

    #expect(open == [try day(2026, 6, 1), try day(2026, 6, 2), try day(2026, 6, 3)])
  }

  // MARK: Private

  private let calendar: Calendar

  private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Timestamp {
    Timestamp(try #require(calendar.date(from: DateComponents(year: year, month: month, day: day))))
  }

  private func work(_ day: Timestamp) -> WorkDay {
    let start = day.adding(seconds: 8 * 3600)
    return WorkDay(day: day, start: start, end: start.adding(seconds: 3600), breaks: [], shortInterruptions: 0, net: 3600)
  }
}
