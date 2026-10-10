import CryptoKit
import Foundation
import Observation
import os
import TaktAnalytics
import TaktCore

// MARK: - MonthCloseModel

/// The month close (AZ-10): archives the previous month's working time record as PDF with a
/// SHA-256 file in a folder and points out working days without a record after 7 days. Whether a
/// month is archived is read from the folder; nothing is stored in the database.
@Observable
public final class MonthCloseModel {

  // MARK: Lifecycle

  public init(
    source: AnalyticsSource,
    analytics: AnalyticsModel,
    settings: AppSettings,
    clock: any TaktClock,
    calendar: Calendar = .current,
    name: (() -> String?)? = nil,
  ) {
    self.source = source
    self.analytics = analytics
    self.settings = settings
    self.clock = clock
    self.calendar = calendar
    // The macOS account's full name, as in the record exported from the analysis screen.
    self.name = name ?? { NSFullUserName().nilIfBlank }
  }

  // MARK: Public

  /// Working days older than 7 days without working time or absence, from the previous month on.
  public private(set) var openDays = [Timestamp]()
  /// The previous month while its record is not in the folder; `nil` before anything was tracked.
  public private(set) var pendingMonth: Range<Timestamp>?
  /// The record written last, to show it in the Finder.
  public private(set) var archivedFile: URL?
  public private(set) var errorMessage: String?

  public var folder: URL? {
    settings.monthCloseFolder.map { URL(filePath: NSString(string: $0).expandingTildeInPath, directoryHint: .isDirectory) }
  }

  /// E.g. "Working time record 2026-09.pdf".
  public func fileName(_ month: Range<Timestamp>) -> String {
    String(localized: "Working time record", bundle: .module) + " "
      + MonthClose.monthString(month.lowerBound, calendar: calendar) + ".pdf"
  }

  public func refresh() async {
    let now = clock.now()
    refreshedDay = now.localDayString(in: calendar)
    do {
      guard let first = try await source.firstTrackedTime() else {
        openDays = []
        pendingMonth = nil
        return
      }
      let previous = MonthClose.previousMonth(of: now, calendar: calendar)
      pendingMonth = previous.flatMap { first < $0.upperBound && !isArchived($0) ? $0 : nil }
      let start = max(first.localDay(in: calendar).lowerBound, previous?.lowerBound ?? first)
      guard start < now else {
        openDays = []
        return
      }
      let range = start..<now
      let data = try await source.load(range, now: now)
      var plan = settings.targetPlan
      plan.absences = try await source.absences(range, calendar: calendar)
      openDays = MonthClose.openDays(
        from: start,
        days: WorkDay.days(in: range, from: data, now: now, calendar: calendar),
        plan: plan,
        now: now,
        calendar: calendar,
      )
    } catch {
      logger.error("Month close check failed: \(String(describing: error), privacy: .private)")
    }
  }

  /// Once a day is enough: the previous month and the 7-day limit only change with the date.
  public func refreshIfNewDay() async {
    guard clock.now().localDayString(in: calendar) != refreshedDay else { return }
    await refresh()
  }

  /// Writes the pending month's record to `folder`, or to the chosen folder, which is then kept.
  @discardableResult
  public func archivePending(to chosen: URL? = nil) async -> URL? {
    if let chosen { settings.monthCloseFolder = chosen.path }
    guard let month = pendingMonth, let folder = chosen ?? folder else { return nil }
    do {
      let url = try await archive(month, in: folder)
      archivedFile = url
      errorMessage = nil
      await refresh()
      return url
    } catch {
      errorMessage = String(localized: "The record could not be archived: \(error.localizedDescription)", bundle: .module)
      logger.error("Month close failed: \(String(describing: error), privacy: .private)")
      return nil
    }
  }

  /// At the start of a month without asking, if the user chose so (AZ-10, off by default).
  public func archiveAutomatically() async {
    await refreshIfNewDay()
    guard settings.monthCloseAutomatic, folder != nil, pendingMonth != nil, errorMessage == nil else { return }
    await archivePending()
  }

  // MARK: Private

  private let source: AnalyticsSource
  private let analytics: AnalyticsModel
  private let settings: AppSettings
  private let clock: any TaktClock
  private let calendar: Calendar
  private let name: () -> String?
  private var refreshedDay: String?
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "month-close")

  private func isArchived(_ month: Range<Timestamp>) -> Bool {
    guard let folder else { return false }
    return FileManager.default.fileExists(atPath: folder.appending(path: fileName(month)).path)
  }

  /// The PDF and next to it `<name>.pdf.sha256` in the format of `shasum -a 256`, so the file can
  /// be checked later. An existing record is never overwritten.
  private func archive(_ month: Range<Timestamp>, in folder: URL) async throws -> URL {
    let export = TimeRecordExport(
      record: try await analytics.timeRecord(in: month),
      name: name(),
      created: clock.now().date,
      version: TimeRecordExport.appVersion,
      calendar: calendar,
    )
    let pdf = export.pdf()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: fileName(month))
    try pdf.write(to: url, options: .withoutOverwriting)
    let digest = SHA256.hash(data: pdf).map { String(format: "%02x", $0) }.joined()
    try Data("\(digest)  \(url.lastPathComponent)\n".utf8)
      .write(to: folder.appending(path: url.lastPathComponent + ".sha256"), options: .atomic)
    return url
  }
}
