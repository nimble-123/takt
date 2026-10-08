import AppKit
import CoreGraphics

/// Presence signals from macOS. Needs neither accessibility nor screen recording permission.
public struct MacActivitySignals: ActivitySignals {

  // MARK: Lifecycle

  public init() { }

  // MARK: Public

  public func secondsSinceLastInput() async -> TimeInterval {
    // `~0` is kCGAnyInputEventType: any keyboard, mouse or trackpad event.
    guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
    return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
  }

  public func events() -> AsyncStream<SystemEvent> {
    AsyncStream { continuation in
      let workspace = NSWorkspace.shared.notificationCenter
      let distributed = DistributedNotificationCenter.default()
      let sources: [(NotificationCenter, Notification.Name, SystemEvent)] = [
        (workspace, NSWorkspace.willSleepNotification, .willSleep),
        (workspace, NSWorkspace.didWakeNotification, .didWake),
        (distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked),
        (distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenUnlocked),
      ]
      let tasks = sources.map { center, name, event in
        Task {
          for await _ in center.notifications(named: name).map({ _ in () }) {
            continuation.yield(event)
          }
        }
      }
      continuation.onTermination = { _ in for task in tasks { task.cancel() } }
    }
  }
}
