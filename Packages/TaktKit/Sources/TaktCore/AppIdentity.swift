// MARK: - AppIdentity

/// Identifiers shared by all modules, e.g. for `os.Logger` subsystems and keychain services.
public enum AppIdentity {
  public static let bundleIdentifier = "de.nilslutz.takt"
  public static let logSubsystem = bundleIdentifier
}

extension Error {
  /// Type and code of the error, safe to log publicly. Its description goes to the log as
  /// `.private`: it can carry titles, notes, URLs or answers from Azure DevOps.
  public var logSummary: String {
    "\(String(reflecting: type(of: self))) \(_code)"
  }
}
