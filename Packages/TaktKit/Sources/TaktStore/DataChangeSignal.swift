import Foundation

/// Tells a running app that another process, e.g. the command line tool (#189), wrote to the
/// database. A Darwin notification carries no data: the app reloads what it shows.
public enum DataChangeSignal {

  public static let name = "de.nilslutz.takt.data-changed"

  /// Sends the signal; does nothing where Darwin notifications do not exist.
  public static func post() {
    #if canImport(Darwin)
    CFNotificationCenterPostNotification(
      CFNotificationCenterGetDarwinNotifyCenter(),
      CFNotificationName(name as CFString),
      nil,
      nil,
      true,
    )
    #endif
  }
}
