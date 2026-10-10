import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktCLI

/// The one-time import of the Excel timesheet (#190).
struct TimesheetImportTests {

  // MARK: Lifecycle

  init() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    calendar.firstWeekday = 2
    session = Session(database: try AppDatabase.inMemory(), clock: clock, calendar: calendar)
    suite = "takt-import-\(UUID().uuidString)"
    defaults = try #require(UserDefaults(suiteName: suite))
  }

  // MARK: Internal

  @Test
  func breakStartsAtNoonAfterSixHoursAtTheLatestOrInTheMiddle() {
    // 07:30–17:00 with 2 h: from 12:00.
    #expect(Session.layout(start: 450, end: 1020, pause: 120) == [450..<720, 840..<1020])
    // 05:00–16:00 with 30 min: 6 h after the start, before noon.
    #expect(Session.layout(start: 300, end: 960, pause: 30) == [300..<660, 690..<960])
    // 08:00–11:30 with 30 min: in the middle.
    #expect(Session.layout(start: 480, end: 690, pause: 30) == [480..<570, 600..<690])
    // 13:00–18:00 with 30 min: in the middle as well.
    #expect(Session.layout(start: 780, end: 1080, pause: 30) == [780..<915, 945..<1080])
    #expect(Session.layout(start: 480, end: 960, pause: 0) == [480..<960])
  }

  @Test
  func blocksSplitTheWorkMinutesAndGiveTheRestToTheLastShare() {
    let meeting = CategoryID()
    let development = CategoryID()
    let blocks = Session.blocks([450..<720, 840..<1020], shares: [(meeting, 33), (development, 67)])
    #expect(blocks.map(\.0) == [meeting, development])
    // 450 minutes: 148 for the meeting, the rest of 302 for development across the break.
    #expect(blocks.first?.1 == [450..<598])
    #expect(blocks.last?.1 == [598..<720, 840..<1020])
  }

  @Test
  func importIsAdditiveAndSkipsDaysWithTime() async throws {
    let development = EntryCategory(name: "Entwicklung", color: "#2563EB")
    try await CatalogStore(database: session.database).save(development)
    try await session.start("Schon erfasst", parallel: false) // Wednesday 7 October
    clock.advance(seconds: 3600)
    try await session.stop(nil)

    let dry = try await session.importTimesheet(sheet, dryRun: true, defaults: defaults, backupFolder: nil)
    #expect(dry.workDays == 1)
    #expect(dry.absences == 1)
    #expect(dry.skipped.map(\.date) == ["2026-10-07"])
    #expect(try await session.log(.week, around: day(2026, 10, 5)).rows.count == 1)

    let result = try await session.importTimesheet(sheet, dryRun: false, defaults: defaults, backupFolder: nil)
    #expect(result.entries == 1)
    let log = try await session.log(.day, around: day(2026, 10, 5))
    #expect(log.rows.map(\.title) == ["Arbeitszeit"])
    #expect(log.totalSeconds == 7.5 * 3600)
    let absences = try await AbsenceStore(database: session.database).absences(from: "2026-10-01", through: "2026-10-31")
    #expect(absences == ["2026-10-06": .vacation])

    let again = try await session.importTimesheet(sheet, dryRun: false, defaults: defaults, backupFolder: nil)
    #expect(again.entries == 0)
    #expect(again.absences == 0)
  }

  @Test
  func monthlyFlexTimeIsComparedAndSettingsAreTakenOverOnRequest() async throws {
    try await CatalogStore(database: session.database).save(EntryCategory(name: "Development", color: "#2563EB"))
    defaults.set(40.0, forKey: "weeklyHours")

    let result = try await session.importTimesheet(
      sheet,
      until: "2026-10-05",
      applySettings: true,
      dryRun: false,
      defaults: defaults,
      backupFolder: nil,
    )

    // 5 October: 7:30 net against 7:36 target.
    #expect(result.months.map(\.taktHours) == [-0.1])
    #expect(result.months.first?.matches == true)
    #expect(result.settings.first { $0.key == "weeklyHours" }?.applied == false)
    #expect(defaults.double(forKey: "weeklyHours") == 40)
    #expect(defaults.double(forKey: "flexStartBalanceHours") == 94.82)
    #expect(defaults.string(forKey: "flexStartDay") == "2026-01-01")
    #expect(defaults.integer(forKey: "vacationCarryoverDays") == 18)
  }

  @Test
  func distributionMustAddUpAndNameKnownCategories() async throws {
    try await CatalogStore(database: session.database).save(EntryCategory(name: "Entwicklung", color: "#2563EB"))
    await #expect(throws: CLIError.invalid("The shares of --distribute must add up to 100.")) {
      try await session.importTimesheet(
        sheet,
        distribution: [("Entwicklung", 90)],
        dryRun: true,
        defaults: defaults,
        backupFolder: nil,
      )
    }
    await #expect(throws: CLIError.notFound("category “Meeting”; create it in Takt first")) {
      try await session.importTimesheet(
        sheet,
        distribution: [("Meeting", 50), ("Entwicklung", 50)],
        dryRun: true,
        defaults: defaults,
        backupFolder: nil,
      )
    }
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000)) // Wed 2026-10-07 10:00 Berlin
  private let session: Session
  private let suite: String
  private let defaults: UserDefaults

  private var sheet: Timesheet {
    Timesheet(
      format: 1,
      year: 2026,
      settings: .init(
        weeklyHours: 38,
        federalState: "BW",
        flexStartBalanceMinutes: 5689,
        vacationCarryoverDays: 18,
        vacationDaysPerYear: 30,
      ),
      days: [
        .init(date: "2026-10-05", start: "07:30", end: "15:30", pauseMinutes: 30, note: nil, absence: nil, flexDay: nil),
        .init(date: "2026-10-06", start: nil, end: nil, pauseMinutes: nil, note: nil, absence: "vacation", flexDay: nil),
        .init(date: "2026-10-07", start: "08:00", end: "16:00", pauseMinutes: 30, note: nil, absence: nil, flexDay: nil),
      ],
      months: [.init(month: "2026-10", flexHours: -0.1)],
      totalFlexHours: nil,
      warnings: [],
    )
  }

  private func day(_ year: Int, _ month: Int, _ day: Int) -> Timestamp {
    Timestamp(session.calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast)
  }
}
