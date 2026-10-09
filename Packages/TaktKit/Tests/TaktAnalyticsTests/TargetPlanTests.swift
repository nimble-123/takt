import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktAnalytics

struct TargetPlanTests {

  // MARK: Lifecycle

  init() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
  }

  // MARK: Internal

  @Test
  func weeklyHoursAreSpreadOverTheWorkDays() {
    let plan = TargetPlan(weeklyHours: 40)
    #expect(plan.target(on: day(0), calendar: calendar) == 8 * 3600)
    #expect(plan.target(on: day(5), calendar: calendar) == 0) // Saturday
    let partTime = TargetPlan(weeklyHours: 30, workDays: [1, 2, 3])
    #expect(partTime.target(on: day(2), calendar: calendar) == 10 * 3600)
    #expect(partTime.target(on: day(3), calendar: calendar) == 0)
  }

  @Test
  func publicHolidaysHaveNoTarget() throws {
    // Thursday 4 June 2026: Corpus Christi in Hesse, not in Berlin.
    let corpusChristi = Timestamp(try #require(calendar.date(from: DateComponents(year: 2026, month: 6, day: 4))))

    #expect(TargetPlan(weeklyHours: 40, federalState: .hesse).target(on: corpusChristi, calendar: calendar) == 0)
    #expect(TargetPlan(weeklyHours: 40, federalState: .berlin).target(on: corpusChristi, calendar: calendar) == 8 * 3600)
    #expect(TargetPlan(weeklyHours: 40).target(on: corpusChristi, calendar: calendar) == 8 * 3600)
  }

  @Test
  func balanceCountsOnlyDaysUpToToday() {
    let entry = TimeEntry(title: "A", createdAt: monday, updatedAt: monday)
    let segments = [
      Segment(entryID: entry.id, start: day(0).adding(seconds: 8 * 3600), end: day(0).adding(seconds: 17 * 3600)),
      Segment(entryID: entry.id, start: day(1).adding(seconds: 8 * 3600), end: day(1).adding(seconds: 14 * 3600)),
    ]
    let data = AnalyticsData(entries: [EntryWithSegments(entry: entry, segments: segments)])
    let week = monday..<day(7)
    let now = day(1).adding(seconds: 15 * 3600) // Tuesday afternoon
    let report = Analyzer(calendar: calendar).report(data, in: week, now: now, by: .day)

    let comparison = TargetPlan().compare(report, now: now, calendar: calendar)
    #expect(comparison.target == 16 * 3600)
    #expect(comparison.actual == 15 * 3600)
    #expect(comparison.balance == -3600)
  }

  @Test
  func invalidInputIsIgnored() {
    let plan = TargetPlan(weeklyHours: -5, workDays: [0, 8])
    #expect(plan.weeklyHours == 0)
    #expect(plan.target(on: day(0), calendar: calendar) == 0)
  }

  // MARK: Private

  private let calendar: Calendar
  /// Monday 2026-10-05, 00:00 in Berlin.
  private let monday = Timestamp(milliseconds: 1_791_151_200_000)

  private func day(_ offset: Double) -> Timestamp {
    monday.adding(seconds: offset * 86_400)
  }

}
