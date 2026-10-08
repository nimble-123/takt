import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktAnalytics

// MARK: - AnalyzerTests

struct AnalyzerTests {

  // MARK: Lifecycle

  init() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
    analyzer = Analyzer(calendar: calendar, defaultMode: .split)
  }

  // MARK: Internal

  @Test
  func groupsByProjectWithSplitAndFullCounting() {
    let portal = ProjectID()
    let meeting = entry("Meeting", [(9, 10)], project: portal)
    let ticket = entry("Ticket", [(9, 11)])
    let data = AnalyticsData(entries: [meeting, ticket])

    let split = analyzer.report(data, in: week, now: at(200), by: .project)
    #expect(split.total == 3 * 3600 - 3600)
    #expect(split.groups.first { $0.key == .project(portal) }?.seconds == 1800)
    #expect(split.groups.first { $0.key == GroupKey.none }?.seconds == 5400)
    #expect(split.wallClock == 7200)
    #expect(split.multitaskingShare == 0.5)

    let full = analyzer.report(data, in: week, now: at(200), by: .project, mode: .full)
    #expect(full.total == 3 * 3600)
  }

  @Test
  func segmentsOverMidnightAreSplitByLocalDay() {
    let late = entry("Release", [(22, 26)])
    let report = analyzer.report(AnalyticsData(entries: [late]), in: week, now: at(200), by: .day)

    #expect(report.days[0].total == 2 * 3600)
    #expect(report.days[1].total == 2 * 3600)
    #expect(report.slices.map(\.day) == [monday, at(24)])
    #expect(report.groups.count == 2)
  }

  @Test
  func rangeClipsSegmentsAndHeatmapUsesLocalHours() {
    let morning = entry("A", [(8.5, 10)])
    let report = analyzer.report(
      AnalyticsData(entries: [morning]),
      in: at(9)..<at(24),
      now: at(200),
      by: .hourOfDay,
    )

    #expect(report.total == 3600)
    #expect(report.heatmap[0][9] == 3600) // Monday 09:00
    #expect(report.groups.map(\.key) == [.hour(9)])
  }

  @Test
  func pausesAreGapsWithinADay() {
    let a = entry("A", [(9, 10), (10.5, 11), (33, 34)])
    let report = analyzer.report(AnalyticsData(entries: [a]), in: week, now: at(200), by: .project)
    #expect(report.pauses == 1800)
  }

  @Test
  func focusBlocksNeedTwentyFiveMinutesWithoutParallelWork() {
    let focus = entry("Focus", [(9, 9.5)])
    let short = entry("Short", [(10, 10.3)])
    let interrupted = entry("Interrupted", [(11, 12)])
    let parallel = entry("Call", [(11.25, 11.5)])
    let report = analyzer.report(
      AnalyticsData(entries: [focus, short, interrupted, parallel]),
      in: week,
      now: at(200),
      by: .project,
    )

    // Focus (30 min) and the 30 min of "Interrupted" after the call; 15 min before it are too short.
    #expect(report.focusBlocks == 2)
    #expect(report.focusTime == 3600)
  }

  @Test
  func contextSwitchesCountNewEntriesButNotPauses() {
    let a = entry("A", [(9, 10), (11, 12)]) // the pause 10–11 is not a switch
    let b = entry("B", [(12, 13)]) // switch
    let c = entry("C", [(12.5, 14)]) // parallel start is a switch
    let tuesday = entry("D", [(33, 34)]) // first entry of a day is no switch
    let report = analyzer.report(AnalyticsData(entries: [a, b, c, tuesday]), in: week, now: at(200), by: .project)

    #expect(report.contextSwitchesPerDay == 1) // 2 switches on 2 days
  }

  @Test
  func tagsCountInEachTagAndUntaggedInNone() {
    let tagged = entry("A", [(9, 10)])
    let untagged = entry("B", [(10, 11)])
    let urgent = Tag(name: "dringend")
    let customer = Tag(name: "Kunde")
    let data = AnalyticsData(entries: [tagged, untagged], tags: [tagged.id: [urgent, customer]])
    let report = analyzer.report(data, in: week, now: at(200), by: .tag)

    #expect(report.groups.first { $0.key == .tag(urgent.id) }?.seconds == 3600)
    #expect(report.groups.first { $0.key == .tag(customer.id) }?.seconds == 3600)
    #expect(report.groups.first { $0.key == GroupKey.none }?.seconds == 3600)
  }

  @Test
  func weekdaysStartOnMonday() {
    let sunday = entry("A", [(6.0 * 24 + 9, 6.0 * 24 + 10)])
    let report = analyzer.report(AnalyticsData(entries: [sunday]), in: week, now: at(200), by: .weekday)
    #expect(report.groups.map(\.key) == [.weekday(7)])
  }

  @Test
  func groupsWithEqualTotalsKeepAStableOrder() {
    // One hour each on Friday, Tuesday and Wednesday, plus one entry without a project.
    let entries = [
      entry("Fr", [(4.0 * 24 + 9, 4.0 * 24 + 10)], project: ProjectID()),
      entry("Tu", [(1.0 * 24 + 9, 1.0 * 24 + 10)]),
      entry("We", [(2.0 * 24 + 9, 2.0 * 24 + 10)], project: ProjectID()),
    ]
    let data = AnalyticsData(entries: entries)

    let byWeekday = analyzer.report(data, in: week, now: at(200), by: .weekday)
    #expect(byWeekday.groups.map(\.key) == [.weekday(2), .weekday(3), .weekday(5)])

    let projects = entries.compactMap(\.entry.projectID).sorted { $0.uuidString < $1.uuidString }
    let byProject = analyzer.report(data, in: week, now: at(200), by: .project)
    #expect(byProject.groups.map(\.key) == projects.map(GroupKey.project) + [GroupKey.none])
  }

  @Test
  func runningSegmentsCountUntilNow() {
    let running = TimeEntry(title: "A", state: .running, createdAt: monday, updatedAt: monday)
    let data = AnalyticsData(entries: [
      EntryWithSegments(entry: running, segments: [Segment(entryID: running.id, start: at(9))])
    ])
    #expect(analyzer.report(data, in: week, now: at(9.5), by: .project).total == 1800)
  }

  @Test
  func previousRangeHasTheSameLength() {
    #expect(Analyzer.previous(week) == at(-7 * 24)..<monday)
  }

  // MARK: Private

  private let analyzer: Analyzer
  private let calendar: Calendar
  /// Monday 2026-10-05, 00:00 in Berlin.
  private let monday = Timestamp(milliseconds: 1_791_151_200_000)

  private var week: Range<Timestamp> {
    monday..<at(7 * 24)
  }

  private func at(_ hours: Double) -> Timestamp {
    monday.adding(seconds: hours * 3600)
  }

  private func entry(
    _ title: String,
    _ ranges: [(Double, Double)],
    project: ProjectID? = nil,
    category: CategoryID? = nil,
    mode: CountingMode? = nil,
  ) -> EntryWithSegments {
    let entry = TimeEntry(
      title: title,
      projectID: project,
      categoryID: category,
      countingMode: mode,
      createdAt: monday,
      updatedAt: monday,
    )
    return EntryWithSegments(
      entry: entry,
      segments: ranges.map { Segment(entryID: entry.id, start: at($0.0), end: at($0.1)) },
    )
  }

}

// MARK: - ExporterTests

struct ExporterTests {
  @Test(arguments: ["=SUM(A1)", "+1", "-2", "@cmd", "\tTab"])
  func csvKeepsFormulaLikeTextAsText(title: String) {
    let row = Exporter.Row(
      date: "2026-10-05",
      title: title,
      project: nil,
      task: nil,
      category: nil,
      tags: [],
      workItem: nil,
      note: nil,
      countingMode: "split",
      seconds: -1800,
      hours: -0.5,
      roundedHours: -0.5,
    )

    let line = Exporter.csv([row]).components(separatedBy: "\r\n")[1]

    #expect(line.hasPrefix("2026-10-05,'\(title),"))
    #expect(line.hasSuffix(",-1800,-0.5,-0.5")) // numbers stay numbers
  }

  @Test
  func csvEscapesAndRoundsPerEntryAndDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    let monday = Timestamp(milliseconds: 1_791_151_200_000)
    let category = EntryCategory(name: "Meeting", color: "#C2410C")
    let entry = TimeEntry(
      title: "Review, \"Login\"",
      categoryID: category.id,
      note: "Zeile 1\nZeile 2",
      createdAt: monday,
      updatedAt: monday,
    )
    let segment = Segment(
      entryID: entry.id,
      start: monday.adding(seconds: 9 * 3600),
      end: monday.adding(seconds: 9 * 3600 + 1400),
    )
    let data = AnalyticsData(
      entries: [EntryWithSegments(entry: entry, segments: [segment])],
      tags: [entry.id: [Tag(name: "Kunde"), Tag(name: "dringend")]],
      catalog: Catalog(categories: [category]),
    )
    let report = Analyzer(calendar: calendar).report(
      data,
      in: monday..<monday.adding(seconds: 86_400),
      now: monday.adding(seconds: 86_400),
      by: .day,
    )

    let rows = Exporter.rows(report, data, rounding: Rounding(minutes: 15), defaultMode: .split, calendar: calendar)
    let csv = Exporter.csv(rows)
    let lines = csv.components(separatedBy: "\r\n")

    #expect(lines[0].hasPrefix("date,title,project"))
    #expect(lines[1].hasPrefix(#"2026-10-05,"Review, ""Login""",,,Meeting,Kunde; dringend,,"Zeile 1"#))
    #expect(rows.first?.hours == 0.3889)
    #expect(rows.first?.roundedHours == 0.5) // 23:20 min rounds to 30 min

    let json = try Exporter.json(rows, range: monday..<monday.adding(seconds: 86_400), calendar: calendar)
    let text = String(decoding: json, as: UTF8.self)
    #expect(text.contains(#""from" : "2026-10-05""#))
    #expect(text.contains(#""to" : "2026-10-05""#))
  }
}
