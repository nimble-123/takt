import Foundation
import Testing

@testable import TaktCore

struct TimestampTests {

  // MARK: Internal

  @Test
  func roundTripsDatesInMilliseconds() {
    let timestamp = Timestamp(milliseconds: 1_790_000_000_123)
    #expect(Timestamp(timestamp.date) == timestamp)
  }

  @Test
  func localDayStartsAtMidnight() {
    // 2026-10-07 10:00 in Berlin (UTC+2)
    let day = Timestamp(milliseconds: 1_791_360_000_000).localDay(in: berlin)
    #expect(day.lowerBound == Timestamp(milliseconds: 1_791_324_000_000))
    #expect(day.upperBound.seconds(since: day.lowerBound) == 86_400)
  }

  @Test
  func dayOfDaylightSavingChangeHas25Hours() {
    // 2026-10-25 12:00 in Berlin; clocks go back at 03:00
    let day = Timestamp(milliseconds: 1_792_926_000_000).localDay(in: berlin)
    #expect(day.upperBound.seconds(since: day.lowerBound) == 25 * 3600)
  }

  // MARK: Private

  private var berlin: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

}
