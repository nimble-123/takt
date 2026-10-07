import ServiceManagement

/// Start at login via `SMAppService.mainApp` (no helper app needed).
public enum LoginItem {
    @MainActor
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app; throws if macOS refuses, e.g. for a build outside /Applications.
    @MainActor
    public static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
