import Foundation
import TaktCore
import Testing

@testable import TaktAnalytics

// MARK: - VacationAccountTests

struct VacationAccountTests {

  // MARK: Lifecycle

  init() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
  }

  // MARK: Internal

  @Test
  func plannedDaysAfterToday() throws {
    let account = account(carryover: 0, startYear: 2026)
    // Monday 5 to Friday 9 October 2026; today is Wednesday 7 October.
    let absences = vacation((5...9).map { "2026-10-0\($0)" })

    let year = account.year(2026, absences: absences, now: try day(2026, 10, 7).adding(seconds: 3600))

    #expect(year.taken == 3)
    #expect(year.planned == 2)
    #expect(year.available == 30)
    #expect(year.left == 25)
  }

  @Test
  func weekendsHolidaysAndOtherAbsencesDoNotCount() throws {
    let account = account(carryover: 0, startYear: 2026)
    // Saturday 3 October is German Unity Day anyway; Friday 2 October is a working day; Thursday
    // 1 October is a sick day; Monday 26 October a day off.
    var absences = vacation(["2026-10-02", "2026-10-03", "2026-10-04", "2026-12-25"])
    absences["2026-10-01"] = .sick
    absences["2026-10-26"] = .off

    let year = account.year(2026, absences: absences, now: try day(2026, 12, 31))

    #expect(year.taken == 1)
  }

  @Test
  func partTimeCountsOnlyItsWorkingDays() throws {
    // Monday to Wednesday.
    let plan = TargetPlan(weeklyHours: 24, workDays: [1, 2, 3], federalState: .hesse)
    let account = VacationAccount(plan: plan, daysPerYear: 18, carryover: 0, startYear: 2026, calendar: calendar)
    let absences = vacation((5...9).map { "2026-10-0\($0)" })

    let year = account.year(2026, absences: absences, now: try day(2026, 12, 31))

    #expect(year.taken == 3)
    #expect(year.left == 15)
  }

  @Test
  func leftDaysCarryOverIntoTheNextYears() throws {
    let account = account(carryover: 4, startYear: 2025)
    // 2025: 4 + 30 − 20 = 14 left; 2026: 14 + 30 − 2 = 42. Tuesdays from 7 January 2025, none of
    // them a public holiday.
    let first = try day(2025, 1, 7).date
    let days2025 = (0..<20).compactMap { offset in
      calendar.date(byAdding: .weekOfYear, value: offset, to: first).map { Timestamp($0).localDayString(in: calendar) }
    }
    let absences = vacation(days2025 + ["2026-04-01", "2026-04-02"])

    let previous = account.year(2025, absences: absences, now: try day(2026, 6, 1))
    let year = account.year(2026, absences: absences, now: try day(2026, 6, 1))

    #expect(previous.left == 14)
    #expect(year.carryover == 14)
    #expect(year.left == 42)
    // None of 2026's vacation before 31 March: all of the carryover is open.
    #expect(year.carryoverOpen == 14)
  }

  @Test
  func vacationUntilMarchUsesTheCarryoverFirst() throws {
    let account = account(carryover: 3, startYear: 2026)
    // Monday 2 and Tuesday 3 March taken, Tuesday 31 March planned; today is 15 March.
    let absences = vacation(["2026-03-02", "2026-03-03", "2026-03-31"])

    let year = account.year(2026, absences: absences, now: try day(2026, 3, 15))

    #expect(year.carryoverOpen == 0)
    #expect(account.year(2026, absences: vacation(["2026-03-02"]), now: try day(2026, 4, 1)).carryoverOpen == 2)
  }

  @Test
  func moreTakenThanAvailableCarriesANegativeRest() throws {
    let account = VacationAccount(
      plan: TargetPlan(),
      daysPerYear: 2,
      carryover: 0,
      startYear: 2025,
      calendar: calendar,
    )
    let absences = vacation(["2025-06-02", "2025-06-03", "2025-06-04"])

    #expect(account.year(2026, absences: absences, now: try day(2026, 1, 5)).carryover == -1)
  }

  @Test
  func yearsBeforeTheStartHaveNoCarryover() throws {
    let account = account(carryover: 5, startYear: 2026)

    let year = account.year(2025, absences: [:], now: try day(2026, 1, 5))

    #expect(year.carryover == 0)
    #expect(year.left == 30)
  }

  // MARK: Private

  private let calendar: Calendar

  private func account(carryover: Int, startYear: Int) -> VacationAccount {
    VacationAccount(
      plan: TargetPlan(weeklyHours: 40, federalState: .hesse),
      daysPerYear: 30,
      carryover: carryover,
      startYear: startYear,
      calendar: calendar,
    )
  }

  private func vacation(_ days: [String]) -> [String: AbsenceKind] {
    Dictionary(uniqueKeysWithValues: days.map { ($0, .vacation) })
  }

  private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Timestamp {
    Timestamp(try #require(calendar.date(from: DateComponents(year: year, month: month, day: day))))
  }
}

extension VacationAccountTests {
  @Test
  func daysInARangeCountOnlyWorkingDays() throws {
    let account = account(carryover: 0, startYear: 2026)
    let absences = vacation(["2026-10-02", "2026-10-03", "2026-10-05", "2026-10-12"])
    let range = try day(2026, 10, 1)..<day(2026, 10, 12)

    #expect(account.days(in: range, absences: absences) == 2)
  }
}
