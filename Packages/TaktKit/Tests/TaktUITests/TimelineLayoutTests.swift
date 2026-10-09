import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

struct TimelineLayoutTests {

  // MARK: Internal

  @Test
  func separateItemsShareOneLane() {
    let layout = TimelineLayout(entries: [entry([(8, 9)]), entry([(9, 10)])], day: day, now: t(12))
    #expect(layout.items.map(\.lane) == [0, 0])
    #expect(layout.items.map(\.laneCount) == [1, 1])
  }

  @Test
  func parallelItemsGetSideBySideLanes() {
    let meeting = entry([(9, 10)])
    let ticket = entry([(9.5, 11)])
    let later = entry([(12, 13)])
    let layout = TimelineLayout(entries: [meeting, ticket, later], day: day, now: t(14))

    let byEntry = Dictionary(uniqueKeysWithValues: layout.items.map { ($0.entryID, $0) })
    #expect(byEntry[meeting.id]?.lane == 0)
    #expect(byEntry[ticket.id]?.lane == 1)
    #expect(byEntry[meeting.id]?.laneCount == 2)
    #expect(byEntry[later.id]?.laneCount == 1)
  }

  @Test
  func pausesBetweenSegmentsAreItems() {
    let layout = TimelineLayout(entries: [entry([(8, 10), (11, 12)])], day: day, now: t(13))
    let pauses = layout.items.filter(\.isPause)
    #expect(pauses.count == 1)
    #expect(pauses.first?.start == t(10) && pauses.first?.end == t(11))
  }

  @Test
  func itemsAreClippedToTheDayAndOpenSegmentsEndNow() {
    let layout = TimelineLayout(entries: [entry([(-2, 1)]), entry([(20, nil)])], day: day, now: t(22))
    let segments = layout.items.filter { !$0.isPause }.sorted { $0.start < $1.start }
    #expect(segments.first?.start == t(0))
    #expect(segments.last?.end == t(22))
  }

  @Test
  func overnightGapIsNotAPauseOfTheDay() {
    let layout = TimelineLayout(entries: [entry([(-5, -4), (9, 10)])], day: day, now: t(11))
    #expect(layout.items.filter(\.isPause).isEmpty)
  }

  @Test
  func todayScrollsToOneHourBeforeNow() {
    #expect(TimelineLayout.initialScrollRow(day: day, now: t(14.5)) == 13)
  }

  @Test
  func otherDaysScrollToTheDefaultRow() {
    #expect(TimelineLayout.initialScrollRow(day: day, now: t(30)) == 8)
    #expect(TimelineLayout.initialScrollRow(day: day, now: t(-5)) == 8)
  }

  @Test
  func scrollRowStaysInsideTheDay() {
    #expect(TimelineLayout.initialScrollRow(day: day, now: t(0.25)) == 0)
    #expect(TimelineLayout.initialScrollRow(day: day, now: t(23.9)) == 22)
    let short = t(0)..<t(23) // spring DST day
    #expect(TimelineLayout.initialScrollRow(day: short, now: t(22.9)) == 21)
    #expect(TimelineLayout.initialScrollRow(day: t(0)..<t(5), now: t(30)) == 4)
  }

  @Test
  func movedBlockKeepsItsClockTimeAcrossDST() {
    var berlin = Calendar(identifier: .gregorian)
    berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    let saturday = Timestamp(milliseconds: 1_792_828_800_000) // Sat 2026-10-24 10:00 CEST
    let sunday = TimelineLayout.movedStart(saturday, days: 1, seconds: 1800, calendar: berlin)
    // Clocks go back that night: 10:30 on Sunday is 24.5 h + 1 h later.
    #expect(sunday.seconds(since: saturday) == 25.5 * 3600)
    let friday = TimelineLayout.movedStart(saturday, days: -1, seconds: -3600, calendar: berlin)
    #expect(friday.seconds(since: saturday) == -25 * 3600)
    #expect(TimelineLayout.movedStart(saturday, days: 0, seconds: 900, calendar: berlin) == saturday.adding(seconds: 900))
  }

  // MARK: Private

  private let day = Timestamp(milliseconds: 0)..<Timestamp(milliseconds: 86_400_000)

  private func t(_ hours: Double) -> Timestamp {
    Timestamp(milliseconds: Int64(hours * 3_600_000))
  }

  private func entry(_ ranges: [(Double, Double?)]) -> EntryWithSegments {
    let entry = TimeEntry(title: "E", createdAt: t(0), updatedAt: t(0))
    return EntryWithSegments(
      entry: entry,
      segments: ranges.map { Segment(entryID: entry.id, start: t($0.0), end: $0.1.map(t)) },
    )
  }

}
