import Foundation
import os
import TaktADO
import TaktAnalytics
import TaktCore
import TaktStore
import TaktSystem
import TaktUI

/// Builds store, engine and view models and runs the background work (recovery, heartbeat,
/// backup, idle detection, long-runner warning, reminder without a timer, month close).
@MainActor
final class Composition {

  // MARK: Lifecycle

  init() throws {
    // TAKT_DATA_DIR keeps test runs away from the real data.
    let url =
      try ProcessInfo.processInfo.environment["TAKT_DATA_DIR"]
        .map { URL(filePath: $0).appending(path: "takt.sqlite") } ?? AppDatabase.defaultURL()
    database = try AppDatabase.open(at: url)
    backup = DatabaseBackup(directory: url.deletingLastPathComponent().appending(path: "Backups"))
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    let queries = EntryQueries(database: database)
    catalog = CatalogModel(store: CatalogStore(database: database), clock: clock)
    rules = RulesModel(store: RuleStore(database: database))
    let accounts = ADOAccounts()
    azureDevOps = AzureDevOpsModel(accounts: accounts, catalog: catalog, clock: clock)
    let cache = WorkItemCache(database: database)
    let records = SyncRecordStore(database: database)
    let service = BookingService(
      accounts: accounts,
      records: records,
      cache: cache,
      entries: queries,
      clock: clock,
    ) { [settings] () -> BookingService.Options in
      // Read on every booking, so changed settings apply at once.
      settings.snapshot.bookingOptions
    }
    booking = BookingCoordinator(
      service: service,
      records: records,
      cache: cache,
      queries: queries,
      settings: settings,
      clock: clock,
    )
    let workItems = AzureDevOpsWorkItems(accounts: accounts, cache: cache, clock: clock)
    let actions = TimerActions(engine: engine, catalog: catalog, rules: rules, workItems: workItems)
    self.actions = actions
    menuBar = MenuBarModel(
      engine: engine,
      queries: queries,
      catalog: catalog,
      clock: clock,
      settings: settings,
      workItems: workItems,
      rules: rules,
      gitBranches: { [settings] () async -> [GitBranch] in
        await settings.snapshot.gitBranches.load()
      },
      actions: actions,
    )
    menuBar.hasAzureDevOps = { [azureDevOps] in !azureDevOps.connections.isEmpty }
    menuBar.bookNow = { [booking] id in await booking.book(entry: id) }
    let analyticsSource = AnalyticsSource(database: database)
    let analytics = AnalyticsModel(source: analyticsSource, settings: settings, clock: clock)
    monthClose = MonthCloseModel(source: analyticsSource, analytics: analytics, settings: settings, clock: clock)
    mainWindow = MainWindowModel(
      engine: engine,
      queries: queries,
      catalog: catalog,
      analytics: analytics,
      settings: settings,
      azureDevOps: azureDevOps,
      booking: booking,
      workItems: workItems,
      search: SearchIndex(database: database),
      rules: rules,
      database: database,
      actions: actions,
      monthClose: monthClose,
      clock: clock,
    )
    idleMonitor = IdleMonitor(engine: engine, signals: MacActivitySignals(), clock: clock) {
      [settings] () -> IdleSettings in settings.snapshot.idle
    }
  }

  // MARK: Internal

  let database: AppDatabase
  let clock: any TaktClock = SystemClock()
  let engine: TimerEngine
  let settings = AppSettings()
  let catalog: CatalogModel
  let rules: RulesModel
  let azureDevOps: AzureDevOpsModel
  let booking: BookingCoordinator
  let actions: TimerActions
  let menuBar: MenuBarModel
  let mainWindow: MainWindowModel
  let monthClose: MonthCloseModel
  let idleMonitor: IdleMonitor
  /// Called when inactivity needs the user's decision, e.g. to open the popover.
  var onIdleNeedsDecision: (@MainActor () -> Void)?

  func launch() {
    tasks.append(
      Task {
        // Recovery must read the heartbeat of the previous run before a new one is written.
        do {
          if try await engine.recoverAfterLaunch(idleThreshold: settings.snapshot.idle.threshold) != nil {
            onIdleNeedsDecision?()
          }
        } catch {
          logger.error("Recovery failed: \(error.logSummary, privacy: .public) \(String(describing: error), privacy: .private)")
        }
        await catalog.seedDefaults()
        await rules.reload()
        actions.onStopped = { [weak self] ids in self?.bookAutomatically(ids) }
        observeOtherProcesses()
        // Bookings left pending by a crash or while offline (TECHNICAL_CONCEPT step 6); network
        // calls, so they must not hold back the menu bar and the window.
        tasks.append(Task { await booking.processPending(force: true) })
        tasks.append(Task { await sendQueueWhenOnline() })
        tasks.append(Task { await menuBar.run() })
        tasks.append(Task { await mainWindow.run() })
        tasks.append(Task { await writeHeartbeats() })
        tasks.append(Task { await runChores() })
        tasks.append(Task { await sendQueueRegularly() })
        tasks.append(Task { await idleMonitor.run() })
        tasks.append(Task { await forwardIdleReturns() })
      }
    )
  }

  // MARK: Private

  private let backup: DatabaseBackup
  private let notifier = Notifier()
  private var longRunners = LongRunnerCheck()
  private var noTimerReminder = NoTimerReminder()
  private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "app")
  private var tasks = [Task<Void, Never>]()

  private func forwardIdleReturns() async {
    for await _ in idleMonitor.returns {
      onIdleNeedsDecision?()
    }
  }

  /// TM-07: once a minute, in a loop of its own, so a slow backup or network never delays it and
  /// a failed chore never skips it; recovery after a crash closes timers at the last heartbeat.
  private func writeHeartbeats() async {
    while !Task.isCancelled {
      do {
        try await engine.heartbeat()
      } catch {
        logger.error("Heartbeat failed: \(String(describing: error), privacy: .private)")
      }
      try? await Task.sleep(for: .seconds(60))
    }
  }

  /// Once a minute: daily backup, long-runner warning, reminder without a timer, token reminder,
  /// today's total. Each chore
  /// on its own, so one failing does not skip the others.
  private func runChores() async {
    while !Task.isCancelled {
      do {
        // Copying the database takes a while: off the main actor.
        try await backup.backupIfNeededInBackground(database, now: clock.now())
      } catch {
        logger.error("Daily backup failed: \(String(describing: error), privacy: .private)")
      }
      do {
        let snapshot = try await engine.snapshot()
        await warnAboutLongRunners(snapshot)
        await remindWhenNoTimerRuns(snapshot)
      } catch {
        logger.error("Timer checks failed: \(String(describing: error), privacy: .private)")
      }
      await remindAboutExpiringTokens()
      // AZ-10: checks once a day; archives only if the user chose so.
      await monthClose.archiveAutomatically()
      await menuBar.refresh()
      try? await Task.sleep(for: .seconds(60))
    }
  }

  /// DO-26: once a minute, if bookings wait; the queue keeps its backoff. Network calls, so they
  /// run apart from the other chores.
  private func sendQueueRegularly() async {
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(60))
      if booking.pendingCount > 0 { await booking.processPending() }
    }
  }

  /// #189: the command line tool writes to the same database and signals it; everything shown
  /// is reloaded then. The composition lives as long as the app, so the observer is never removed.
  private func observeOtherProcesses() {
    CFNotificationCenterAddObserver(
      CFNotificationCenterGetDarwinNotifyCenter(),
      Unmanaged.passUnretained(self).toOpaque(),
      { _, observer, _, _, _ in
        guard let observer else { return }
        let composition = Unmanaged<Composition>.fromOpaque(observer).takeUnretainedValue()
        Task { @MainActor in
          composition.settings.reloadFromDefaults()
          await composition.mainWindow.dataWasReplaced()
        }
      },
      DataChangeSignal.name as CFString,
      nil,
      .deliverImmediately,
    )
  }

  /// DO-21: book right after stopping, if the user chose so.
  private func bookAutomatically(_ ids: [EntryID]) {
    guard settings.bookingMode == .automatic else { return }
    Task {
      for id in ids {
        await booking.book(entry: id)
      }
    }
  }

  /// DO-26: the offline queue goes out as soon as the network is back. The state at launch is not
  /// reported, so this does not repeat the launch run; only a return skips the backoff.
  private func sendQueueWhenOnline() async {
    for await online in NetworkMonitor.changes() where online {
      await booking.processPending(force: true)
    }
  }

  /// DO-01: once a day per organization, starting 14 days before the token expires.
  private func remindAboutExpiringTokens() async {
    let day = clock.now().localDay().lowerBound.milliseconds
    for connection in azureDevOps.expiringSoon {
      let key = "adoExpiryReminded-\(connection.organization)"
      guard UserDefaults.standard.object(forKey: key) as? Int64 != day else { continue }
      UserDefaults.standard.set(day, forKey: key)
      await notifier.post(
        id: key,
        title: String(localized: "Azure DevOps token expires soon"),
        body: String(
          localized: "Renew the token for \(connection.organization) and enter it in Takt's settings."
        ),
      )
    }
  }

  /// TM-09: during working hours, while the user is at the Mac, but no timer runs.
  private func remindWhenNoTimerRuns(_ snapshot: TimerSnapshot) async {
    let idle = await MacActivitySignals().secondsSinceLastInput()
    let due = noTimerReminder.check(
      isRunning: !snapshot.running.isEmpty,
      secondsSinceLastInput: idle,
      now: clock.now(),
      settings: settings.noTimerReminder,
    )
    guard due else { return }
    await notifier.post(
      id: "no-timer",
      title: String(localized: "No timer running"),
      body: String(localized: "It's working time, but Takt isn't recording. Start a timer from the menu bar."),
    )
  }

  /// TM-08: a timer running for more than 10 hours was probably forgotten.
  private func warnAboutLongRunners(_ snapshot: TimerSnapshot) async {
    for active in longRunners.check(snapshot, now: clock.now()) {
      await notifier.post(
        id: "long-runner-\(active.id.uuidString)",
        title: String(localized: "Timer running for over 10 hours"),
        body: String(localized: "\(active.entry.title) is still running. Forgot to stop it?"),
      )
    }
  }
}
