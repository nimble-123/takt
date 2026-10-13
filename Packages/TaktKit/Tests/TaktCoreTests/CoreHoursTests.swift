import Foundation
import TaktCore
import Testing

// MARK: - CoreHoursTests

struct CoreHoursTests {

  // MARK: Internal

  @Test
  func aWorkingDayIsShadedBeforeAndAfterTheCoreHours() throws {
    // Tuesday.
    let day = try local(2026, 10, 13).localDay(in: calendar)

    let off = CoreHours().offHours(in: day, isHoliday: false, calendar: calendar)

    #expect(off == [day.lowerBound..<(try local(2026, 10, 13, 6)), (try local(2026, 10, 13, 19))..<day.upperBound])
  }

  @Test
  func aDayOffIsShadedCompletely() throws {
    // Saturday.
    let day = try local(2026, 10, 17).localDay(in: calendar)

    #expect(CoreHours().offHours(in: day, isHoliday: false, calendar: calendar) == [day])
  }

  @Test
  func aPublicHolidayIsShadedCompletely() throws {
    let day = try local(2026, 10, 13).localDay(in: calendar)

    #expect(CoreHours().offHours(in: day, isHoliday: true, calendar: calendar) == [day])
  }

  @Test
  func theCoreHoursFollowTheWallClockOnADaylightSavingChange() throws {
    // Sunday with 25 hours; clocks go back at 3:00.
    let day = try local(2026, 10, 25).localDay(in: calendar)
    let hours = CoreHours(startMinute: 7 * 60 + 30, endMinute: 19 * 60, workDays: Set(1...7))

    let off = hours.offHours(in: day, isHoliday: false, calendar: calendar)

    #expect(off.map(\.upperBound).first == (try local(2026, 10, 25, 7, 30)))
    #expect(off.map(\.lowerBound).last == (try local(2026, 10, 25, 19)))
  }

  @Test
  func emptyCoreHoursShadeTheWholeDay() throws {
    let day = try local(2026, 10, 13).localDay(in: calendar)
    let hours = CoreHours(startMinute: 19 * 60, endMinute: 6 * 60)

    #expect(hours.offHours(in: day, isHoliday: false, calendar: calendar) == [day])
  }

  // MARK: Private

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    return calendar
  }

  private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) throws -> Timestamp {
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
    return Timestamp(try #require(calendar.date(from: components)))
  }
}
