import Foundation
import TaktCore
import Testing

@testable import TaktAnalytics

// MARK: - TimeRecordTests

struct TimeRecordTests {

  // MARK: Lifecycle

  init() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
  }

  // MARK: Internal

  @Test
  func rowsOfAConstructedWeek() throws {
    let record = try week()
    let rows = record.rows

    #expect(rows.map(\.date) == [
      "2026-09-28",
      "2026-09-29",
      "2026-09-30",
      "2026-10-01",
      "2026-10-02",
      "2026-10-03",
      "2026-10-04",
    ])
    // Monday: 8:00–17:00 with 30 minutes break.
    #expect(TimeRecord.time(rows[0].start, calendar: calendar) == "08:00")
    #expect(TimeRecord.time(rows[0].end, calendar: calendar) == "17:00")
    #expect(TimeRecord.duration(rows[0].breakTime) == "0:30")
    #expect(TimeRecord.duration(rows[0].net) == "8:30")
    #expect(rows[0].findings.map(\.rule) == [.dailyEightHours])
    #expect(rows[0].corrected)
    // Tuesday: 11 hours without a break, 14 hours after Monday's end.
    #expect(Set(rows[1].findings.map(\.rule)) == [.dailyTenHours, .breaks, .continuousWork])
    #expect(TimeRecord.duration(rows[1].restBefore) == "14:00")
    #expect(!rows[1].corrected)
    // Wednesday vacation, Saturday German Unity Day; neither has a target.
    #expect(rows[2].absence == .vacation)
    #expect(rows[2].target == 0)
    #expect(rows[5].holiday == .germanUnity)
    // Flex time: +0:30, +3:00, 0, −8:00 (Thursday counts in full), later days are in the future.
    #expect(rows.prefix(4).map { TimeRecord.duration($0.cumulative) } == ["2:30", "5:30", "5:30", "-2:30"])
    #expect(rows[4].target == nil)
    #expect(record.totals.net == 19.5 * 3600)
    #expect(record.totals.beyondEightHours == 3.5 * 3600)
    #expect(record.totals.findings[.dailyTenHours] == 1)
  }

  @Test
  func trustBasedWorkingTimeHasNoBalances() throws {
    let record = try week(flex: false)
    #expect(record.rows.allSatisfy { $0.target == nil && $0.cumulative == nil })
    #expect(!record.csv(calendar: calendar).contains("-2:30"))
  }

  @Test
  func anEmptyPeriodStillListsEveryDay() throws {
    let start = try day(2026, 10, 5)
    let record = TimeRecord.make(
      range: start..<start.adding(seconds: 3 * 86400),
      checks: [],
      segments: [],
      changes: [],
      absences: [:],
      federalState: nil,
      flex: nil,
      now: start,
      calendar: calendar,
    )
    #expect(record.rows.count == 3)
    #expect(record.rows.allSatisfy { $0.start == nil && $0.net == 0 })
    #expect(record.totals.net == 0)
  }

  @Test
  func theCanonicalDataIsStable() throws {
    let first = try week().canonical(calendar: calendar)
    #expect(first == (try week().canonical(calendar: calendar)))
    #expect(first != (try week(extraChange: true).canonical(calendar: calendar)))
  }

  @Test
  func csvHasTheDaysTotalsAndChangeLog() throws {
    let csv = try week().csv(calendar: calendar)
    let lines = csv.components(separatedBy: "\r\n")
    #expect(lines[0].hasPrefix("date,weekday,holiday,absence,start,end,break,net,rest_before"))
    #expect(lines[1] == "2026-09-28,1,,,08:00,17:00,0:30,8:30,,8:00,0:30,2:30,0:30,,dailyEightHours,yes")
    #expect(csv.contains("total_net,19:30"))
    #expect(csv.contains("changed,"))
  }

  // MARK: Private

  private let calendar: Calendar

  private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Timestamp {
    Timestamp(try #require(calendar.date(from: DateComponents(year: year, month: month, day: day))))
  }

  private func work(_ day: Timestamp, _ blocks: [(Double, Double)]) -> WorkDay {
    let spans = blocks.map { day.adding(seconds: $0.0 * 3600)..<day.adding(seconds: $0.1 * 3600) }
    return WorkDay(
      day: day,
      start: spans[0].lowerBound,
      end: spans[spans.count - 1].upperBound,
      breaks: zip(spans, spans.dropFirst()).map { $0.upperBound..<$1.lowerBound },
      shortInterruptions: 0,
      net: spans.reduce(0) { $0 + $1.upperBound.seconds(since: $1.lowerBound) },
    )
  }

  /// Monday 28 September to Sunday 4 October 2026 in Hesse; "now" is Thursday evening.
  private func week(flex: Bool = true, extraChange: Bool = false) throws -> TimeRecord {
    let monday = try day(2026, 9, 28)
    let days = [work(monday, [(8, 12), (12.5, 17)]), work(monday.adding(seconds: 86400), [(7, 18)])]
    let checks = WorkTimeRules(calendar: calendar, federalState: .hesse).check(days)
    let entry = try #require(EntryID(uuidString: "00000000-0000-0000-0000-000000000001"))
    let segment = try #require(SegmentID(uuidString: "00000000-0000-0000-0000-000000000002"))
    let manual = Segment(
      entryID: entry,
      start: monday.adding(seconds: 8 * 3600),
      end: monday.adding(seconds: 12 * 3600),
      source: .manual,
    )
    var changes = [
      SegmentChangeRecord(
        id: try #require(SegmentChangeID(uuidString: "00000000-0000-0000-0000-000000000003")),
        segmentID: segment,
        entryID: entry,
        kind: .changed,
        oldStart: monday.adding(seconds: 13 * 3600),
        oldEnd: monday.adding(seconds: 17 * 3600),
        newStart: monday.adding(seconds: 12.5 * 3600),
        newEnd: monday.adding(seconds: 17 * 3600),
        changedAt: monday.adding(seconds: 18 * 3600),
      )
    ]
    if extraChange {
      changes.append(SegmentChangeRecord(
        segmentID: segment,
        entryID: entry,
        kind: .deleted,
        oldStart: monday,
        oldEnd: monday.adding(seconds: 60),
        changedAt: monday.adding(seconds: 19 * 3600),
      ))
    }
    var plan = TargetPlan(weeklyHours: 40, federalState: .hesse)
    plan.absences = ["2026-09-30": .vacation]
    return TimeRecord.make(
      range: monday..<monday.adding(seconds: 7 * 86400),
      checks: checks,
      segments: [manual],
      changes: changes,
      absences: plan.absences,
      federalState: .hesse,
      flex: flex ? (plan, 2 * 3600, monday) : nil,
      now: monday.adding(seconds: 3 * 86400 + 20 * 3600),
      calendar: calendar,
    )
  }
}

// MARK: - Carryover limit (AZ-08)

extension TimeRecordTests {
  @Test
  func flexAccountIsCappedAtTheYearChangeAndTheForfeitIsListed() throws {
    let plan = TargetPlan(weeklyHours: 0)
    let opening: TimeInterval = 15 * 3600
    let range = try day(2025, 12, 30)..<day(2026, 1, 3)
    let record = TimeRecord.make(
      range: range,
      checks: [],
      segments: [],
      changes: [],
      absences: [:],
      federalState: nil,
      flex: (plan, opening, try day(2025, 12, 1)),
      carryoverLimit: 10 * 3600,
      now: try day(2026, 1, 5),
      calendar: calendar,
    )

    let expected: [TimeInterval?] = [15 * 3600, 15 * 3600, 10 * 3600, 10 * 3600]
    #expect(record.rows.map(\.cumulative) == expected)
    let forfeited: [Int: TimeInterval] = [2025: 5 * 3600]
    #expect(record.totals.forfeited == forfeited)
    #expect(record.csv(calendar: calendar).contains("forfeited_end_of_2025,5:00\r\n"))
  }
}
