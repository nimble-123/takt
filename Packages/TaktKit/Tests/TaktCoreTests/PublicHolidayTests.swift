import Foundation
import Testing

@testable import TaktCore

struct PublicHolidayTests {

  // MARK: Internal

  @Test(arguments: [
    (2024, 3, 31),
    (2025, 4, 20),
    (2026, 4, 5),
    (2027, 3, 28),
    (2038, 4, 25),
    (2285, 3, 22),
  ])
  func easterSunday(year: Int, month: Int, day: Int) {
    #expect(PublicHoliday.easterSunday(in: year) == PublicHoliday.Day(year: year, month: month, day: day))
  }

  @Test(arguments: FederalState.allCases)
  func holidays2026MatchTheReferenceList(state: FederalState) {
    let expected = (Self.nationwide2026 + (Self.regional2026[state] ?? [])).sorted { $0.0 < $1.0 }
    let actual = PublicHoliday.all(in: 2026, state: state)

    #expect(actual.map(\.holiday) == expected.map(\.1))
    #expect(actual.map(\.date) == expected.map(\.0))
  }

  @Test
  func movableHolidays2027() {
    let bavaria = Dictionary(uniqueKeysWithValues: PublicHoliday.all(in: 2027, state: .bavaria).map { ($0.holiday, $0.date) })
    #expect(bavaria[.goodFriday] == day(2027, 3, 26))
    #expect(bavaria[.easterMonday] == day(2027, 3, 29))
    #expect(bavaria[.ascension] == day(2027, 5, 6))
    #expect(bavaria[.whitMonday] == day(2027, 5, 17))
    #expect(bavaria[.corpusChristi] == day(2027, 5, 27))
    #expect(PublicHoliday.all(in: 2027, state: .saxony).contains { $0 == (day(2027, 11, 17), .repentance) })
    #expect(PublicHoliday.all(in: 2027, state: .brandenburg).contains { $0 == (day(2027, 5, 16), .whitSunday) })
  }

  @Test
  func holidaysThatStartedLater() {
    #expect(!PublicHoliday.all(in: 2022, state: .mecklenburgWesternPomerania).contains { $0.holiday == .womensDay })
    #expect(PublicHoliday.all(in: 2023, state: .mecklenburgWesternPomerania).contains { $0.holiday == .womensDay })
    #expect(!PublicHoliday.all(in: 2018, state: .thuringia).contains { $0.holiday == .childrensDay })
    #expect(PublicHoliday.all(in: 2017, state: .bavaria).contains { $0.holiday == .reformation })
    #expect(!PublicHoliday.all(in: 2016, state: .hamburg).contains { $0.holiday == .reformation })
  }

  @Test
  func holidayOnALocalDay() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    // 23:30 local on 2 October is already 3 October in no time zone, but must not count.
    let evening = Timestamp(try #require(calendar.date(from: DateComponents(
      year: 2026,
      month: 10,
      day: 2,
      hour: 23,
      minute: 30,
    ))))
    let unity = Timestamp(try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 0, minute: 30))))

    #expect(PublicHoliday.on(evening, state: .hesse, calendar: calendar) == nil)
    #expect(PublicHoliday.on(unity, state: .hesse, calendar: calendar) == .germanUnity)
  }

  // MARK: Private

  private static let nationwide2026: [(PublicHoliday.Day, PublicHoliday)] = [
    (d(1, 1), .newYear),
    (d(4, 3), .goodFriday),
    (d(4, 6), .easterMonday),
    (d(5, 1), .labourDay),
    (d(5, 14), .ascension),
    (d(5, 25), .whitMonday),
    (d(10, 3), .germanUnity),
    (d(12, 25), .christmasDay),
    (d(12, 26), .boxingDay),
  ]

  private static let regional2026: [FederalState: [(PublicHoliday.Day, PublicHoliday)]] = [
    .badenWuerttemberg: [(d(1, 6), .epiphany), (d(6, 4), .corpusChristi), (d(11, 1), .allSaints)],
    .bavaria: [(d(1, 6), .epiphany), (d(6, 4), .corpusChristi), (d(11, 1), .allSaints)],
    .berlin: [(d(3, 8), .womensDay)],
    .brandenburg: [(d(4, 5), .easterSunday), (d(5, 24), .whitSunday), (d(10, 31), .reformation)],
    .bremen: [(d(10, 31), .reformation)],
    .hamburg: [(d(10, 31), .reformation)],
    .hesse: [(d(6, 4), .corpusChristi)],
    .mecklenburgWesternPomerania: [(d(3, 8), .womensDay), (d(10, 31), .reformation)],
    .lowerSaxony: [(d(10, 31), .reformation)],
    .northRhineWestphalia: [(d(6, 4), .corpusChristi), (d(11, 1), .allSaints)],
    .rhinelandPalatinate: [(d(6, 4), .corpusChristi), (d(11, 1), .allSaints)],
    .saarland: [(d(6, 4), .corpusChristi), (d(8, 15), .assumption), (d(11, 1), .allSaints)],
    .saxony: [(d(10, 31), .reformation), (d(11, 18), .repentance)],
    .saxonyAnhalt: [(d(1, 6), .epiphany), (d(10, 31), .reformation)],
    .schleswigHolstein: [(d(10, 31), .reformation)],
    .thuringia: [(d(9, 20), .childrensDay), (d(10, 31), .reformation)],
  ]

  private static func d(_ month: Int, _ day: Int) -> PublicHoliday.Day {
    PublicHoliday.Day(year: 2026, month: month, day: day)
  }

  private func day(_ year: Int, _ month: Int, _ day: Int) -> PublicHoliday.Day {
    PublicHoliday.Day(year: year, month: month, day: day)
  }
}
