import Foundation
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
        menuBar = MenuBarModel(engine: engine, queries: queries, catalog: catalog, clock: clock, settings: settings)
        mainWindow = MainWindowModel(
            engine: engine, queries: queries, catalog: catalog,
            analytics: AnalyticsModel(source: AnalyticsSource(database: database), clock: clock),
            settings: settings, database: database, clock: clock
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
            } catch {
                logger.error("Background chore failed: \(String(describing: error), privacy: .public)")
            }
            await menuBar.refresh()
            try? await Task.sleep(for: .seconds(60))
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
