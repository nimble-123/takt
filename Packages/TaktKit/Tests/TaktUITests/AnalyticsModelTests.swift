import CoreGraphics
import Foundation
import TaktAnalytics
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

// MARK: - AnalyticsModelTests

@MainActor
struct AnalyticsModelTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    calendar.firstWeekday = 2
    self.calendar = calendar
    testDefaults = try TestDefaults("takt-analytics")
    settings = AppSettings(defaults: testDefaults.defaults)
    model = AnalyticsModel(
      source: AnalyticsSource(database: database),
      settings: settings,
      clock: clock,
      calendar: calendar,
    )
  }

  // MARK: Internal

  @Test
  func rangesFollowThePeriod() {
    model.period = .day
    #expect(model.range.upperBound.seconds(since: model.range.lowerBound) == 86_400)
    model.period = .week
    #expect(Exporter.dayString(model.range.lowerBound, calendar: calendar) == "2026-10-05")
    model.period = .month
    #expect(model.range.upperBound.seconds(since: model.range.lowerBound) == 31 * 86_400 + 3600)
  }

  @Test
  func previousMonthIsTheCalendarMonthBefore() async {
    model.period = .month
    await model.reload()
    #expect(model.report.map { Exporter.dayString($0.range.lowerBound, calendar: calendar) } == "2026-10-01")
    let previous = model.previous?.range
    #expect(previous.map { Exporter.dayString($0.lowerBound, calendar: calendar) } == "2026-09-01")
    #expect(previous?.upperBound == model.range.lowerBound)
  }

  @Test
  func drilldownListsTheEntriesOfAGroup() async throws {
    let project = Project(name: "Portal", color: "#2563EB", createdAt: clock.now())
    try await CatalogStore(database: database).save(project)
    try await track("A", project: project.id, hours: 1)
    try await track("B", hours: 0.5)
    model.period = .day
    await model.reload()

    #expect(model.report?.total == 5400)
    model.drilldown = .project(project.id)
    #expect(model.drilldownEntries.map(\.entry.title) == ["A"])
    model.drilldown = GroupKey.none
    #expect(model.drilldownEntries.map(\.entry.title) == ["B"])
    #expect(model.label(.project(project.id)) == "Portal")
  }

  @Test
  func exportUsesTheShownRange() async throws {
    try await track("A", hours: 1)
    model.period = .day
    await model.reload()

    let csv = String(decoding: try model.export(.csv), as: UTF8.self)
    #expect(csv.contains("2026-10-07,A,"))
    #expect(model.exportFileName == "Takt 2026-10-07 – 2026-10-07")
  }

  @Test
  func exportOfACustomPeriodUsesTheAppliedDates() async throws {
    try await track("A", hours: 1)
    model.period = .custom
    model.customStart = clock.now().date
    model.customEnd = clock.now().date
    await model.reload()

    // Picked, but not applied yet: the report still shows 7 October.
    model.customStart = clock.now().adding(seconds: -2 * 86_400).date
    let json = String(decoding: try model.export(.json), as: UTF8.self)

    #expect(model.exportFileName == "Takt 2026-10-07 – 2026-10-07")
    #expect(json.contains("\"from\" : \"2026-10-07\""))
  }

  @Test
  func hourLabelsFollowTheLocaleClock() {
    var calendar = calendar
    calendar.locale = Locale(identifier: "de_DE")
    #expect(calendar.hourLabel(14) == "14:00")
    calendar.locale = Locale(identifier: "en_US")
    let label = calendar.hourLabel(14)
    // The space before "PM" differs between ICU versions.
    #expect(label.hasPrefix("2:00") && label.hasSuffix("PM"))
  }

  @Test
  func hourGroupsUseTheCalendarsClock() {
    var calendar = calendar
    calendar.locale = Locale(identifier: "en_US")
    let model = AnalyticsModel(
      source: AnalyticsSource(database: database),
      settings: settings,
      clock: clock,
      calendar: calendar,
    )
    #expect(model.label(.hour(9)) == calendar.hourLabel(9))
    #expect(model.label(.hour(9)) != "09:00")
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000)) // Wed 2026-10-07 10:00 Berlin
  private let database: AppDatabase
  private let testDefaults: TestDefaults
  private let settings: AppSettings
  private let model: AnalyticsModel
  private let calendar: Calendar

  private func track(_ title: String, project: ProjectID? = nil, hours: Double) async throws {
    let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    let id = try await engine.start(EntryDraft(title: title, projectID: project), mode: .switchTo).value
    clock.advance(seconds: hours * 3600)
    try await engine.stop(id)
  }

}

extension AnalyticsModelTests {
  @Test
  func pdfReportHasASummaryAndTablePages() async throws {
    for index in 0..<40 {
      try await track("Eintrag \(index)", hours: 0.1)
    }
    model.period = .day
    await model.reload()

    let data = try model.export(.pdf)
    #expect(data.starts(with: Data("%PDF".utf8)))
    let provider = try #require(CGDataProvider(data: data as CFData))
    let document = try #require(CGPDFDocument(provider))
    #expect(document.numberOfPages == 3) // summary, then 40 rows on two table pages
    try? data.write(to: FileManager.default.temporaryDirectory.appending(path: "takt-report-test.pdf"))
  }

  @Test
  func balanceComparesWithTheWeeklyHours() async throws {
    try await track("A", hours: 2)
    model.period = .day
    await model.reload()
    let comparison = try #require(model.comparison)
    #expect(comparison.actual == 2 * 3600)
    #expect(comparison.target == model.targetPlan.target(on: clock.now(), calendar: calendar))
  }
}

// MARK: - Flex account (AZ-05)

extension AnalyticsModelTests {

  // MARK: Internal

  @Test
  func flexAccountCountsFromTheStartDayWithoutAbsences() async throws {
    settings.flexStartDay = "2026-10-05"
    settings.flexStartBalanceHours = 2
    try await track("A", hours: 1)
    await model.reload()
    // Monday to Wednesday: 2 h + 1 h − 3 × 8 h.
    #expect(model.flexBalance == TimeInterval(-21 * 3600))

    try await AbsenceStore(database: database).set(.vacation, on: "2026-10-05")
    await model.reload()
    #expect(model.flexBalance == TimeInterval(-13 * 3600))
    #expect(model.targetHours(on: try day(2026, 10, 5)) == 0)
    #expect(model.targetHours(on: try day(2026, 10, 6)) == 8)
  }

  @Test
  func trustBasedWorkingTimeHasNoTargetAndNoAccount() async throws {
    settings.workTimeModel = .trust
    try await track("A", hours: 1)
    await model.reload()

    #expect(model.flexBalance == nil)
    #expect(model.comparison == nil)
    #expect(model.targetHours(on: try day(2026, 10, 6)) == 0)
  }

  // MARK: Private

  private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Timestamp {
    Timestamp(try #require(calendar.date(from: DateComponents(year: year, month: month, day: day))))
  }
}

// MARK: - Working time record (AZ-09)

extension AnalyticsModelTests {
  @Test
  func timeRecordOfTheShownWeek() async throws {
    try await track("A", hours: 2)
    model.period = .week
    await model.reload()

    let record = try await model.timeRecord()

    #expect(record.rows.count == 7)
    let wednesday = try #require(record.rows.first { $0.date == "2026-10-07" })
    #expect(wednesday.net == 2 * 3600)
    #expect(TimeRecord.time(wednesday.start, calendar: calendar) == "10:00")
    #expect(!wednesday.corrected)
    // Flex time by default, counted from the first tracked day: 2 h − 8 h.
    #expect(record.rows.first?.cumulative == nil)
    #expect(wednesday.cumulative == TimeInterval(-6 * 3600))
  }

  @Test
  func timeRecordExportHasAStableChecksumAndPages() async throws {
    try await track("A", hours: 2)
    model.period = .week
    await model.reload()
    let record = try await model.timeRecord()
    let created = Date(timeIntervalSince1970: 1_791_400_000)

    let named = TimeRecordExport(record: record, name: "Nils", created: created, version: "1.0", calendar: calendar)
    let anonymous = TimeRecordExport(record: record, name: nil, created: created, version: "1.0", calendar: calendar)

    #expect(named.checksum.count == 64)
    #expect(named.checksum == anonymous.checksum)
    let csv = String(decoding: anonymous.csv(), as: UTF8.self)
    #expect(csv.hasPrefix("record,working_time_record\r\nname,\r\n"))
    #expect(csv.contains("sha256,\(named.checksum)"))
    let pdf = try #require(CGPDFDocument(CGDataProvider(data: named.pdf() as CFData)!))
    // One page of days and one with the totals; no change log without changes.
    #expect(pdf.numberOfPages == 2)
  }
}

// MARK: - Vacation account (AZ-06)

extension AnalyticsModelTests {

  // MARK: Internal

  @Test
  func vacationAccountOfTheCurrentYear() async throws {
    settings.flexStartDay = "2026-01-01"
    settings.vacationDaysPerYear = 28
    settings.vacationCarryoverDays = 3
    try await setVacation(on: ["2026-03-02", "2026-10-05", "2026-10-09", "2026-10-10"])
    await model.reload()

    let vacation = try #require(model.vacation)
    // Today is Wednesday 7 October; Saturday 10 October is no working day.
    #expect(vacation.taken == 2)
    #expect(vacation.planned == 1)
    #expect(vacation.left == 28)
    let open = try #require(model.openCarryover)
    #expect(open.days == 2)
    #expect(open.deadlinePassed)
  }

  @Test
  func timeRecordListsTheVacationOfThePeriod() async throws {
    try await track("A", hours: 2)
    try await setVacation(on: ["2026-10-05", "2026-10-09"])
    model.period = .week
    await model.reload()

    let vacation = try #require(try await model.timeRecord().vacation)

    #expect(vacation.days == 2)
    #expect(vacation.account.taken == 1)
    #expect(vacation.account.planned == 1)
    #expect(vacation.account.left == 28)
    let csv = try await model.timeRecord().csv(calendar: calendar)
    #expect(csv.contains("vacation_days,2\r\n"))
  }

  // MARK: Private

  private func setVacation(on days: [String]) async throws {
    let store = AbsenceStore(database: database)
    for day in days {
      try await store.set(.vacation, on: day)
    }
  }
}
