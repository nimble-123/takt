import Foundation
import Testing

@testable import TaktCore

struct LocalDayPartsTests {

  // MARK: Internal

  @Test
  func weekdayStartsOnMondayWhateverTheCalendarSays() {
    // 2026-10-07 10:00 in Berlin, a Wednesday
    let wednesday = Timestamp(milliseconds: 1_791_360_000_000)
    let sunday = wednesday.adding(seconds: 4 * 86_400)
    var mondayFirst = berlin
    mondayFirst.firstWeekday = 2
    #expect(wednesday.mondayBasedWeekday(in: berlin) == 3)
    #expect(wednesday.mondayBasedWeekday(in: mondayFirst) == 3)
    #expect(sunday.mondayBasedWeekday(in: berlin) == 7)
  }

  @Test
  func localDayStringRoundTripsThroughItsParts() throws {
    let day = Timestamp(milliseconds: 1_791_360_000_000).localDayString(in: berlin)
    let parts = try #require(Timestamp.localDayParts(day))
    #expect(parts.year == 2026)
    #expect(parts.month == 10)
    #expect(parts.day == 7)
  }

  @Test(arguments: ["", "2026-10", "2026-10-07-1", "2026-x-07", "2026--07"])
  func otherShapesHaveNoParts(_ string: String) {
    #expect(Timestamp.localDayParts(string) == nil)
  }

  // MARK: Private

  private var berlin: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

}
