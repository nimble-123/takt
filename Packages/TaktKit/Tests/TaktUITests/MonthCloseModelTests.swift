import CryptoKit
import Foundation
import TaktAnalytics
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

@MainActor
struct MonthCloseModelTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
    testDefaults = try TestDefaults("takt-month-close")
    settings = AppSettings(defaults: testDefaults.defaults)
    let source = AnalyticsSource(database: database)
    model = MonthCloseModel(
      source: source,
      analytics: AnalyticsModel(source: source, settings: settings, clock: clock, calendar: calendar),
      settings: settings,
      clock: clock,
      calendar: calendar,
      name: { "Nils" },
    )
    folder = FileManager.default.temporaryDirectory.appending(path: "takt-month-close-\(UUID().uuidString)")
  }

  // MARK: Internal

  @Test
  func nothingIsPendingBeforeAnythingWasTracked() async {
    await model.refresh()
    #expect(model.pendingMonth == nil)
    #expect(model.openDays.isEmpty)
  }

  @Test
  func openDaysStartAtTheFirstTrackedDayAndSkipAbsences() async throws {
    try await trackSeptember()
    try await AbsenceStore(database: database).set(.vacation, on: "2026-09-25")

    await model.refresh()

    // Wednesday 7 October: days until Tuesday 29 September are more than 7 days old.
    #expect(model.openDays.map { $0.localDayString(in: calendar) } == ["2026-09-24", "2026-09-28", "2026-09-29"])
    #expect(model.pendingMonth?.lowerBound.localDayString(in: calendar) == "2026-09-01")
  }

  @Test
  func archivingWritesThePDFAndItsChecksumOnce() async throws {
    try await trackSeptember()
    await model.refresh()
    defer { try? FileManager.default.removeItem(at: folder) }

    let url = try #require(await model.archivePending(to: folder))

    #expect(url.lastPathComponent == "Working time record 2026-09.pdf")
    #expect(settings.monthCloseFolder == folder.path)
    let pdf = try Data(contentsOf: url)
    let digest = SHA256.hash(data: pdf).map { String(format: "%02x", $0) }.joined()
    let checksum = try String(contentsOf: url.appendingPathExtension("sha256"), encoding: .utf8)
    #expect(checksum == "\(digest)  Working time record 2026-09.pdf\n")
    #expect(model.pendingMonth == nil)
    #expect(await model.archivePending() == nil)
  }

  @Test
  func automaticArchivingOnlyWhenSwitchedOn() async throws {
    try await trackSeptember()
    settings.monthCloseFolder = folder.path
    defer { try? FileManager.default.removeItem(at: folder) }

    await model.archiveAutomatically()
    #expect(model.pendingMonth != nil)

    settings.monthCloseAutomatic = true
    await model.archiveAutomatically()
    #expect(model.pendingMonth == nil)
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Working time record 2026-09.pdf").path))
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_790_150_400_000)) // Wed 2026-09-23 10:00 Berlin
  private let database: AppDatabase
  private let testDefaults: TestDefaults
  private let settings: AppSettings
  private let model: MonthCloseModel
  private let calendar: Calendar
  private let folder: URL

  /// One hour on Wednesday 23 September, then the clock moves to Wednesday 7 October 10:00.
  private func trackSeptember() async throws {
    let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    let id = try await engine.start(EntryDraft(title: "Konzept"), mode: .switchTo).value
    clock.advance(seconds: 3600)
    try await engine.stop(id)
    clock.advance(seconds: 14 * 86_400 - 3600)
  }
}
