import Foundation
import TaktADO
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

@MainActor
struct BookingCoordinatorTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    self.calendar = calendar
    cache = WorkItemCache(database: database)
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    let records = SyncRecordStore(database: database)
    let accounts = ADOAccounts(
      secrets: KeychainStore(service: "takt-tests-unused"),
      suiteName: "takt-bc-\(UUID().uuidString)",
    )
    let service = BookingService(
      accounts: accounts,
      records: records,
      cache: cache,
      entries: EntryQueries(database: database),
      clock: clock,
    ) { BookingService.Options() }
    let settings = AppSettings(
      defaults: UserDefaults(suiteName: "takt-bc-settings-\(UUID().uuidString)") ?? .standard
    )
    settings.roundingMinutes = 15
    coordinator = BookingCoordinator(
      service: service,
      records: records,
      cache: cache,
      queries: EntryQueries(database: database),
      settings: settings,
      clock: clock,
      calendar: calendar,
    )
  }

  // MARK: Internal

  @Test
  func linesUseTheSettingsAndShowFailuresWithoutRecording() async throws {
    let link = try #require(
      try await cache.store([
        WorkItemLink(organization: "contoso", project: "P", workItemID: 1, cachedType: "Task")
      ]).first
    )
    let id = try await engine.start(EntryDraft(title: "A", workItemLinkID: link.id), mode: .switchTo).value
    clock.advance(seconds: 20 * 60)
    try await engine.stop(id)

    let day = clock.now().localDay(in: calendar)
    let lines = try await coordinator.lines(for: day)
    #expect(lines.map(\.target) == [15 * 60]) // 20 min rounded to the quarter hour

    let outcomes = await coordinator.book(lines)
    #expect(outcomes.values.first == .failed(.notConnected))
    #expect(try await coordinator.records.records(onDay: "2026-10-07").isEmpty)
    #expect(coordinator.pendingCount == 0)
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000)) // 2026-10-07 10:00 Berlin
  private let database: AppDatabase
  private let coordinator: BookingCoordinator
  private let cache: WorkItemCache
  private let engine: TimerEngine
  private let calendar: Calendar

}
