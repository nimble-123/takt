import Foundation
import TaktCore
import Testing

@testable import TaktAnalytics

struct WorkTimeRulesTests {

  // MARK: Lifecycle

  init() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
    rules = WorkTimeRules(calendar: calendar)
  }

  // MARK: Internal

  @Test
  func eightHoursAreFineMoreIsAWarningMoreThanTenAViolation() {
    #expect(findings(work(0, [(8, 12), (12.5, 16.5)])).isEmpty)
    #expect(findings(work(0, [(8, 12), (12.75, 17.75)])) == [.dailyEightHours])
    let ten = rules.check([work(0, [(7, 12), (12.75, 17.75)])])[0]
    #expect(ten.findings.map(\.rule) == [.dailyEightHours])
    #expect(findings(work(0, [(7, 12), (12.75, 18)])) == [.dailyTenHours])
    #expect(rules.check([work(0, [(7, 12), (12.75, 18)])])[0].severity == .violation)
  }

  @Test
  func breaksAfterSixAndNineHours() {
    // Exactly 6:00 needs no break.
    #expect(findings(work(0, [(8, 14)])).isEmpty)
    #expect(findings(work(0, [(8, 11), (11.25, 14.5)])) == [.breaks])
    #expect(findings(work(0, [(8, 11), (11.5, 14.75)])).isEmpty)
    // Exactly 9:00 needs 30 minutes, more than 9 needs 45.
    #expect(findings(work(0, [(8, 12.5), (13, 17.5)])) == [.dailyEightHours])
    #expect(findings(work(0, [(8, 12.5), (13, 17.75)])) == [.breaks, .dailyEightHours])
    #expect(findings(work(0, [(8, 12.5), (13.25, 18)])) == [.dailyEightHours])
  }

  @Test
  func noMoreThanSixHoursInARow() {
    let check = rules.check([work(0, [(7, 13.25), (14, 15)])])[0]

    #expect(check.findings.map(\.rule) == [.continuousWork])
    #expect(check.findings[0].measured == 6.25 * 3600)
    #expect(findings(work(0, [(7, 13), (13.75, 15)])).isEmpty)
  }

  @Test
  func restPeriodIsAlwaysMeasured() {
    let checks = rules.check([
      work(0, [(9, 13), (13.5, 17)]),
      work(1, [(4, 8)]),
      work(2, [(9, 13)]),
    ])

    #expect(checks[0].restBefore == nil)
    // Exactly 11 hours is enough.
    #expect(checks[1].restBefore == TimeInterval(11 * 3600))
    #expect(checks[1].findings.isEmpty)
    #expect(checks[2].restBefore == TimeInterval(25 * 3600))

    let short = rules.check([work(0, [(9, 13), (13.5, 17.25)]), work(1, [(4, 8)])])[1]
    #expect(short.findings.map(\.rule) == [.restPeriod])
    #expect(short.findings[0].measured == 10.75 * 3600)
  }

  @Test
  func sundaysAndHolidaysAreReported() {
    let sunday = work(6, [(10, 12)])
    #expect(findings(sunday) == [.sundayOrHoliday])
    #expect(rules.check([sunday])[0].severity == .notice)

    // Saturday 3 October 2026, German Unity Day, only with a federal state.
    let unity = work(-2, [(10, 12)])
    #expect(findings(unity).isEmpty)
    let hesse = WorkTimeRules(calendar: calendar, federalState: .hesse)
    #expect(hesse.check([unity])[0].findings.map(\.rule) == [.sundayOrHoliday])
  }

  @Test
  func averageOverTwentyFourWeeks() {
    // The 24 weeks up to Monday: 9.5 hours Mon–Fri make 47.5 h per week, under 48 h.
    let window = -167...0
    let normal = window.filter { (1...5).contains(weekday($0)) }.map { work($0, [(7, 12), (12.75, 17.25)]) }
    #expect(rules.check(normal).last?.findings.contains { $0.rule == .averageEightHours } == false)

    // Plus four hours on each Saturday: 51.5 h per week.
    let saturdays = window.filter { weekday($0) == 6 }.map { work($0, [(8, 12)]) }
    #expect(saturdays.count == 24)
    let heavy = (normal + saturdays).sorted { $0.day < $1.day }
    let average = rules.check(heavy).last?.findings.first { $0.rule == .averageEightHours }
    #expect(average?.severity == .violation)
    #expect(abs((average?.measured ?? 0) - 51.5 * 3600 / 6) < 1)
  }

  // MARK: Private

  private let calendar: Calendar
  private let rules: WorkTimeRules
  /// Monday 2026-10-05, 00:00 in Berlin.
  private let monday = Timestamp(milliseconds: 1_791_151_200_000)

  /// 1 = Monday … 7 = Sunday, `offset` days after Monday.
  private func weekday(_ offset: Int) -> Int {
    ((offset % 7) + 7) % 7 + 1
  }

  private func findings(_ day: WorkDay) -> [WorkTimeFinding.Rule] {
    rules.check([day])[0].findings.map(\.rule)
  }

  /// A working day `offset` days after Monday with blocks from–to in local hours.
  private func work(_ offset: Int, _ blocks: [(Double, Double)]) -> WorkDay {
    let day = Timestamp(calendar.date(byAdding: .day, value: offset, to: monday.date) ?? monday.date)
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
}
