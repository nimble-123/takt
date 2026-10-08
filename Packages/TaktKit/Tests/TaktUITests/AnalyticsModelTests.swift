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
