import AppKit
import Foundation
import os
import TaktCore
import TaktStore
import TaktSystem

/// Resets Takt to the state of a first launch: all data, the settings and the Azure DevOps
/// connections with their tokens. The daily backups stay as a safety net.
enum FactoryReset {

  /// Deletes everything; the caller relaunches the app afterwards.
  static func run(
    database: AppDatabase,
    azureDevOps: AzureDevOpsModel?,
    defaults: UserDefaults = .standard,
    domain: String? = Bundle.main.bundleIdentifier,
    disableLoginItem: () -> Void = { try? LoginItem.setEnabled(false) },
  ) async throws {
    // Tokens first: they live in the Keychain, not in the settings.
    for connection in azureDevOps?.connections ?? [] {
      azureDevOps?.disconnect(connection.organization)
    }
    try await DatabaseArchive.eraseAll(database)
    disableLoginItem()
    if let domain { defaults.removePersistentDomain(forName: domain) }
  }

  /// Starts a new instance, with the test data folder if one is set, and quits this one.
  static func relaunch() {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.createsNewApplicationInstance = true
    if let folder = ProcessInfo.processInfo.environment["TAKT_DATA_DIR"] {
      configuration.environment = ["TAKT_DATA_DIR": folder]
    }
    NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
      if let error {
        Logger(subsystem: AppIdentity.logSubsystem, category: "settings")
          .error("Relaunch after reset failed: \(error.logSummary, privacy: .public)")
      }
      Task { @MainActor in NSApp.terminate(nil) }
    }
  }

  /// The critical confirmation; `true` if the user chose to reset.
  static func confirm() -> Bool {
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = String(localized: "Reset Takt to factory settings?", bundle: .module)
    alert.informativeText = String(
      localized: "All entries, projects, categories, rules, bookings, settings and Azure DevOps connections are deleted, and Takt starts as on first launch. The daily backups stay. This cannot be undone.",
      bundle: .module,
    )
    alert.addButton(withTitle: String(localized: "Cancel", bundle: .module))
    let reset = alert.addButton(withTitle: String(localized: "Reset", bundle: .module))
    reset.hasDestructiveAction = true
    return alert.runModal() == .alertSecondButtonReturn
  }
}
