import Foundation
import TaktADO
import TaktAnalytics
import TaktCore
import TaktStore
import TaktSystem
import TaktUI
import os

/// Builds store, engine and view models and runs the background work (recovery, heartbeat,
/// backup, idle detection, long-runner warning).
@MainActor
final class Composition {
    let database: AppDatabase
    let clock: any TaktClock = SystemClock()
    let engine: TimerEngine
    let settings = AppSettings()
    let catalog: CatalogModel
    let rules: RulesModel
    let azureDevOps: AzureDevOpsModel
    let booking: BookingCoordinator
    let menuBar: MenuBarModel
    let mainWindow: MainWindowModel
    let idleMonitor: IdleMonitor
    /// Called when inactivity needs the user's decision, e.g. to open the popover.
    var onIdleNeedsDecision: (@MainActor () -> Void)?

    private let backup: DatabaseBackup
    private let notifier = Notifier()
    private var longRunners = LongRunnerCheck()
    private let logger = Logger(subsystem: AppIdentity.logSubsystem, category: "app")
    private var tasks: [Task<Void, Never>] = []

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
            accounts: accounts, records: records, cache: cache, entries: queries, clock: clock
        ) {
            // Read on every booking, so changed settings apply at once.
            let defaults = UserDefaults.standard
            return BookingService.Options(
                reduceRemainingWork: defaults.object(forKey: "reduceRemainingWork") as? Bool ?? true,
                includeNote: defaults.object(forKey: "bookingIncludesNote") as? Bool ?? true
            )
        }
        booking = BookingCoordinator(
            service: service, records: records, cache: cache, queries: queries, settings: settings, clock: clock
        )
        let workItems = AzureDevOpsWorkItems(accounts: accounts, cache: cache, clock: clock)
        menuBar = MenuBarModel(
            engine: engine, queries: queries, catalog: catalog, clock: clock, settings: settings,
            workItems: workItems, rules: rules
        )
        mainWindow = MainWindowModel(
            engine: engine, queries: queries, catalog: catalog,
            analytics: AnalyticsModel(source: AnalyticsSource(database: database), clock: clock),
            settings: settings, azureDevOps: azureDevOps, booking: booking, workItems: workItems,
            search: SearchIndex(database: database), rules: rules,
            database: database, clock: clock
        )
        idleMonitor = IdleMonitor(engine: engine, signals: MacActivitySignals(), clock: clock) {
            Self.idleSettings()
        }
    }

    /// Settings come from `UserDefaults`, where MDM profiles can also set them.
    nonisolated static func idleSettings() -> IdleSettings {
        let defaults = UserDefaults.standard
        let minutes = defaults.object(forKey: "idleThresholdMinutes") as? Int ?? 10
        return IdleSettings(
            threshold: TimeInterval(max(1, minutes) * 60),
            lockCountsAsPause: defaults.bool(forKey: "lockCountsAsPause")
        )
    }

    func launch() {
        tasks.append(
            Task {
                // Recovery must read the heartbeat of the previous run before a new one is written.
                do {
                    if try await engine.recoverAfterLaunch(idleThreshold: Self.idleSettings().threshold) != nil {
                        onIdleNeedsDecision?()
                    }
                } catch {
                    logger.error("Recovery failed: \(String(describing: error), privacy: .public)")
                }
                await catalog.seedDefaults()
                await rules.reload()
                // Bookings left pending by a crash or while offline (TECHNICAL_CONCEPT step 6).
                await booking.processPending(force: true)
                menuBar.onStopped = { [weak self] ids in self?.bookAutomatically(ids) }
                tasks.append(Task { await sendQueueWhenOnline() })
                tasks.append(Task { await menuBar.run() })
                tasks.append(Task { await mainWindow.run() })
                tasks.append(Task { await runChores() })
                tasks.append(Task { await idleMonitor.run() })
                tasks.append(Task { await forwardIdleReturns() })
            }
        )
    }

    private func forwardIdleReturns() async {
        for await _ in idleMonitor.returns {
            onIdleNeedsDecision?()
        }
    }

    /// Once a minute: heartbeat, daily backup, today's total, long-runner warning.
    private func runChores() async {
        while !Task.isCancelled {
            do {
                try await engine.heartbeat()
                try backup.backupIfNeeded(database, now: clock.now())
                await warnAboutLongRunners(try await engine.snapshot())
                await remindAboutExpiringTokens()
                if booking.pendingCount > 0 { await booking.processPending() }
            } catch {
                logger.error("Background chore failed: \(String(describing: error), privacy: .public)")
            }
            await menuBar.refresh()
            try? await Task.sleep(for: .seconds(60))
        }
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

    /// DO-26: the offline queue goes out as soon as the network is back.
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
                    localized: "Renew the token for \(connection.organization) and enter it in Takt's settings.")
            )
        }
    }

    /// TM-08: a timer running for more than 10 hours was probably forgotten.
    private func warnAboutLongRunners(_ snapshot: TimerSnapshot) async {
        for active in longRunners.check(snapshot, now: clock.now()) {
            await notifier.post(
                id: "long-runner-\(active.id.uuidString)",
                title: String(localized: "Timer running for over 10 hours"),
                body: String(localized: "\(active.entry.title) is still running. Forgot to stop it?")
            )
        }
    }
}
