import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktAnalytics

struct WorkDayTests {

  // MARK: Lifecycle

  init() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
  }

  // MARK: Internal

  @Test
  func gapsUnderFifteenMinutesCountAsWorkLongerOnesAreBreaks() throws {
    let morning = entry([(8, 10), (10.2, 12)])
    let afternoon = entry([(12.5, 17)])

    let day = try #require(days([morning, afternoon]).first)

    #expect(day.day == monday)
    #expect(day.start == at(8))
    #expect(day.end == at(17))
    #expect(day.breaks == [at(12)..<at(12.5)])
    #expect(abs(day.shortInterruptions - 0.2 * 3600) < 1)
    #expect(abs(day.net - 8.5 * 3600) < 1)
    #expect(abs(day.breakTime - 1800) < 1)
  }

  @Test
  func aGapOfExactlyFifteenMinutesIsABreak() throws {
    let day = try #require(days([entry([(9, 10), (10.25, 11)])]).first)

    #expect(day.breaks == [at(10)..<at(10.25)])
    #expect(day.net == 1.75 * 3600)
  }

  @Test
  func parallelTimeCountsOnce() throws {
    let call = entry([(9, 11)], mode: .full)
    let ticket = entry([(10, 12)], mode: .full)

    let day = try #require(days([call, ticket]).first)

    #expect(day.net == 3 * 3600)
    #expect(day.breaks.isEmpty)
  }

  @Test
  func categoriesThatAreNotWorkAreLeftOut() throws {
    let errand = EntryCategory(name: "Private", color: "#888888", countsAsWork: false)
    let work = EntryCategory(name: "Development", color: "#0F766E")
    let data = AnalyticsData(
      entries: [entry([(9, 12)], category: work.id), entry([(12, 13)], category: errand.id), entry([(13, 15)])],
      catalog: Catalog(categories: [errand, work]),
    )

    let day = try #require(WorkDay.days(in: week, from: data, now: at(200), calendar: calendar).first)

    #expect(day.breaks == [at(12)..<at(13)])
    #expect(day.net == 5 * 3600)
  }

  @Test
  func workPastMidnightStaysOnTheDayItBegan() {
    let late = entry([(20, 26)])
    let next = entry([(32, 40)])

    let result = days([late, next])

    #expect(result.map(\.day) == [monday, at(24)])
    #expect(result[0].end == at(26))
    #expect(result[0].net == 6 * 3600)
    #expect(result[1].start == at(32))
  }

  @Test
  func aRunningTimerCountsUntilNow() throws {
    let running = entry([(9, 10)], openFrom: 10.1)

    let day = try #require(days([running], now: at(11)).first)

    #expect(day.end == at(11))
    #expect(abs(day.net - 2 * 3600) < 1)
  }

  @Test
  func onlyDaysBeginningInTheRangeAreReturned() {
    let sunday = entry([(-2, 1)])
    let result = days([sunday, entry([(9, 10)])])

    #expect(result.map(\.day) == [monday])
  }

  @Test
  func dstChangeCountsRealTime() throws {
    // Sunday, 25 October 2026: clocks go back from 03:00 to 02:00 in Berlin.
    let midnight = Timestamp(try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 25))))
    let start = midnight.adding(seconds: 3600)
    let end = midnight.adding(seconds: 5 * 3600)
    let night = EntryWithSegments(
      entry: TimeEntry(title: "Release", createdAt: start, updatedAt: start),
      segments: [],
    )
    var data = AnalyticsData(entries: [night])
    data.entries[0].segments = [Segment(entryID: night.id, start: start, end: end)]

    let day = try #require(
      WorkDay.days(in: midnight..<midnight.adding(seconds: 25 * 3600), from: data, now: end, calendar: calendar).first
    )

    #expect(day.day == midnight)
    #expect(day.net == 4 * 3600)
    #expect(calendar.component(.hour, from: day.end.date) == 4)
  }

  // MARK: Private

  private let calendar: Calendar
  /// Monday 2026-10-05, 00:00 in Berlin.
  private let monday = Timestamp(milliseconds: 1_791_151_200_000)

  private var week: Range<Timestamp> {
    monday..<at(7 * 24)
  }

  private func at(_ hours: Double) -> Timestamp {
    monday.adding(seconds: hours * 3600)
  }

  private func days(_ entries: [EntryWithSegments], now: Timestamp? = nil) -> [WorkDay] {
    WorkDay.days(in: week, from: AnalyticsData(entries: entries), now: now ?? at(200), calendar: calendar)
  }

  private func entry(
    _ ranges: [(Double, Double)],
    category: CategoryID? = nil,
    mode: CountingMode? = nil,
    openFrom: Double? = nil,
  ) -> EntryWithSegments {
    let entry = TimeEntry(title: "Work", categoryID: category, countingMode: mode, createdAt: monday, updatedAt: monday)
    var segments = ranges.map { Segment(entryID: entry.id, start: at($0.0), end: at($0.1)) }
    if let openFrom { segments.append(Segment(entryID: entry.id, start: at(openFrom))) }
    return EntryWithSegments(entry: entry, segments: segments)
  }
}
