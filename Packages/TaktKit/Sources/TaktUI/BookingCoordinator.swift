import Foundation
import Observation
import os
import TaktADO
import TaktCore
import TaktStore

// MARK: - BookingCoordinator

/// Builds booking lines for days and books them; shared by the day close, the inspector and the
/// automatic booking when stopping (DO-20, DO-21).
@MainActor
@Observable
public final class BookingCoordinator {

  // MARK: Lifecycle

  public init(
    service: BookingService,
    records: SyncRecordStore,
    cache: WorkItemCache,
    queries: EntryQueries,
    settings: AppSettings,
    clock: any TaktClock,
    calendar: Calendar = .current,
  ) {
    self.service = service
    self.records = records
    self.cache = cache
    self.queries = queries
    self.settings = settings
    self.clock = clock
    self.calendar = calendar
  }

  // MARK: Public

  /// Bookings not confirmed yet (offline queue, DO-26).
  public private(set) var pendingCount = 0

  /// Lines of a local day: entries with a work item and earlier bookings of that day.
  public func lines(for day: Range<Timestamp>) async throws -> [BookingLine] {
    let localDay = day.lowerBound.localDayString(in: calendar)
    let now = clock.now()
    let entries = try await queries.timeline(in: day, now: now).entries
    let dayRecords = try await records.records(onDay: localDay)
    var links = [WorkItemLinkID: WorkItemLink]()
    for id in Set(entries.compactMap(\.entry.workItemLinkID) + dayRecords.map(\.workItemLinkID)) {
      links[id] = try await cache.link(id)
    }
    var deletedTitles = [EntryID: String]()
    for id in Set(dayRecords.map(\.entryID)).subtracting(entries.map(\.id)) {
      deletedTitles[id] = try await queries.entry(id)?.title
    }
    return BookingPlanner.lines(
      entries: entries,
      workItems: links,
      records: dayRecords,
      day: day,
      localDay: localDay,
      now: now,
      defaultMode: settings.countingMode,
      rounding: settings.rounding,
      deletedTitles: deletedTitles,
    )
  }

  @discardableResult
  public func book(_ lines: [BookingLine]) async -> [BookingLine.Key: BookingService.Outcome] {
    let outcomes = await service.book(lines)
    await refreshPending()
    return outcomes
  }

  /// Books an entry on every day it has time in the last 31 days, e.g. after stopping it.
  public func book(entry id: EntryID) async {
    do {
      guard let entry = try await queries.entry(id) else { return }
      let since = clock.now().adding(seconds: -31 * 86_400)
      let segments =
        try await queries.timeline(in: since..<clock.now().adding(seconds: 1), now: clock.now())
          .entries.first { $0.id == entry.id }?.segments ?? []
      var days = Set<Timestamp>()
      for segment in segments {
        var day = segment.start.localDay(in: calendar)
        while day.lowerBound < (segment.end ?? clock.now()) {
          days.insert(day.lowerBound)
          day = day.upperBound.localDay(in: calendar)
        }
      }
      for start in days.sorted() {
        let lines = try await lines(for: start.localDay(in: calendar)).filter { $0.entryID == id }
        await book(lines)
      }
    } catch {
      logger.error("Booking an entry failed: \(String(describing: error), privacy: .public)")
    }
  }

  /// Sends the queue again; on launch, when the network returns and on request.
  @discardableResult
  public func processPending(force: Bool = false) async -> Int {
    let remaining = await service.processPending(force: force)
    await refreshPending()
    return remaining
  }

  /// Successfully booked seconds per entry, for the inspector (HW-02).
  public func bookedSeconds(of entries: [EntryID]) async -> [EntryID: Int] {
    let all = (try? await records.records(for: entries)) ?? []
    return Dictionary(grouping: all.filter { $0.status == .synced }, by: \.entryID)
      .mapValues { $0.reduce(0) { $0 + $1.deltaSeconds } }
  }

  // MARK: Internal

  let service: BookingService
  let records: SyncRecordStore

  // MARK: Private

  private let cache: WorkItemCache
  private let queries: EntryQueries
  private let settings: AppSettings
  private let clock: any TaktClock
  private let calendar: Calendar
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "booking")

  private func refreshPending() async {
    pendingCount = (try? await records.pending().count) ?? 0
  }
}

extension BookingFailure {
  /// Shown in the day close.
  var message: String {
    switch self {
    case .notConnected: String(localized: "Not connected to this organization.", bundle: .module)
    case .workItemUnknown: String(localized: "The work item is unknown.", bundle: .module)
    case .unauthorized: String(localized: "Azure DevOps rejected the token.", bundle: .module)
    case .workItemGone: String(localized: "The work item no longer exists.", bundle: .module)
    case .keepsChanging: String(localized: "The work item kept changing; try again.", bundle: .module)
    case .server: String(localized: "Azure DevOps reported an error.", bundle: .module)
    }
  }
}
