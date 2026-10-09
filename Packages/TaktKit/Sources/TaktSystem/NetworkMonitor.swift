import Network
import Synchronization

// MARK: - NetworkMonitor

/// Reports whether the network is usable, so queued bookings go out once it is back (DO-26).
public enum NetworkMonitor {
  /// Changes after the state at launch: `true` when a usable path appears again, `false` when it
  /// goes away. Repeated reports, e.g. when Wi-Fi hands over to Ethernet, are left out.
  public static func changes() -> AsyncStream<Bool> {
    AsyncStream { continuation in
      let reachability = Mutex(Reachability())
      let monitor = NWPathMonitor()
      monitor.pathUpdateHandler = { path in
        if let online = reachability.withLock({ $0.change(to: path.status == .satisfied) }) {
          continuation.yield(online)
        }
      }
      monitor.start(queue: DispatchQueue(label: "de.nilslutz.takt.network"))
      continuation.onTermination = { _ in monitor.cancel() }
    }
  }
}

// MARK: - Reachability

/// The last reported state, so that only real changes count.
struct Reachability {
  /// The new state if it differs from the last report; nil for the first report and repeats.
  mutating func change(to online: Bool) -> Bool? {
    defer { last = online }
    guard let last, last != online else { return nil }
    return online
  }

  private var last: Bool?
}
