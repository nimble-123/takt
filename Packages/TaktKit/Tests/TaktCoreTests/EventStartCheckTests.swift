import Testing

@testable import TaktCore

// MARK: - EventStartCheckTests

struct EventStartCheckTests {

  // MARK: Internal

  @Test
  func announcesEventsOfOfferingSeriesOnceWhenTheyBegin() {
    var check = EventStartCheck()
    let daily = event("daily", series: "s1", at: 120)
    #expect(check.check([daily], rules: rules, now: at(60)).isEmpty)
    #expect(check.check([daily], rules: rules, now: at(125)) == [daily])
    #expect(check.check([daily], rules: rules, now: at(185)).isEmpty)
  }

  @Test
  func ignoresSeriesWithoutTheOptionAndSingleEvents() {
    var check = EventStartCheck()
    let events = [event("other", series: "s2", at: 30), event("single", series: nil, at: 30)]
    #expect(check.check(events, rules: rules, now: at(60)).isEmpty)
  }

  @Test
  func firstCheckOnlyLooksOneMinuteBack() {
    var check = EventStartCheck()
    let events = [event("old", series: "s1", at: 0), event("new", series: "s1", at: 100)]
    #expect(check.check(events, rules: rules, now: at(120)).map(\.id) == ["new"])
  }

  // MARK: Private

  private let rules = [
    "s1": SeriesRule(seriesID: "s1", offersTimerAtStart: true),
    "s2": SeriesRule(seriesID: "s2", endsWithEvent: true),
  ]

  private func at(_ seconds: Int64) -> Timestamp {
    Timestamp(milliseconds: 1_790_000_000_000 + seconds * 1000)
  }

  private func event(_ id: String, series: String?, at seconds: Int64) -> CalendarEvent {
    CalendarEvent(
      id: id,
      seriesID: series,
      title: id,
      start: at(seconds),
      end: at(seconds + 900),
      attendeeCount: 0,
      isOnlineMeeting: false,
      isPrivate: false,
    )
  }
}

// MARK: - UntrackedEventsTests

struct UntrackedEventsTests {

  // MARK: Internal

  @Test
  func eventWithoutTimeIsUntracked() {
    #expect(CalendarEvent.untracked([event], segments: [], now: at(7200)).map(\.id) == ["e"])
  }

  @Test
  func eventCoveredMostlyIsTracked() {
    let segment = Segment(entryID: EntryID(), start: at(600), end: at(3600))
    #expect(CalendarEvent.untracked([event], segments: [segment], now: at(7200)).isEmpty)
  }

  @Test
  func eventCoveredLessThanHalfStaysAndFutureEventsAreLeftOut() {
    let segment = Segment(entryID: EntryID(), start: at(0), end: at(900))
    #expect(CalendarEvent.untracked([event], segments: [segment], now: at(7200)).map(\.id) == ["e"])
    #expect(CalendarEvent.untracked([event], segments: [], now: at(-60)).isEmpty)
  }

  @Test
  func runningEventCountsOnlyUpToNow() {
    let segment = Segment(entryID: EntryID(), start: at(0), end: nil)
    #expect(CalendarEvent.untracked([event], segments: [segment], now: at(600)).isEmpty)
  }

  // MARK: Private

  /// 0:00–1:00.
  private let event = CalendarEvent(
    id: "e",
    seriesID: nil,
    title: "Review",
    start: Timestamp(milliseconds: 1_790_000_000_000),
    end: Timestamp(milliseconds: 1_790_003_600_000),
    attendeeCount: 0,
    isOnlineMeeting: false,
    isPrivate: false,
  )

  private func at(_ seconds: Int64) -> Timestamp {
    Timestamp(milliseconds: 1_790_000_000_000 + seconds * 1000)
  }
}
