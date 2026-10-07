import Foundation
import TaktCore
import TaktStore
import TaktUI
import os

/// Builds store, engine and view models and runs the background chores (heartbeat, backup).
@MainActor
final class Composition {
    /// Inactivity threshold until the idle detection makes it configurable (TM-06).
    static let idleThreshold: TimeInterval = 10 * 60

    let database: AppDatabase
    let clock: any TaktClock = SystemClock()
    let engine: TimerEngine
    let menuBar: MenuBarModel
    private let backup: DatabaseBackup
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
        menuBar = MenuBarModel(engine: engine, queries: EntryQueries(database: database), clock: clock)
    }

    func launch() {
        let engine = engine
        let menuBar = menuBar
        tasks.append(
            Task {
                do {
                    try await engine.recoverAfterLaunch(idleThreshold: Self.idleThreshold)
                } catch {
                    logger.error("Recovery failed: \(String(describing: error), privacy: .public)")
                }
                await menuBar.run()
            }
        )
        tasks.append(Task { await self.runChores() })
    }

    /// Once a minute: heartbeat, daily backup, today's total.
    private func runChores() async {
        while !Task.isCancelled {
            do {
                try await engine.heartbeat()
                try backup.backupIfNeeded(database, now: clock.now())
            } catch {
                logger.error("Background chore failed: \(String(describing: error), privacy: .public)")
            }
            await menuBar.refresh()
            try? await Task.sleep(for: .seconds(60))
        }
    }
}
