import Network

/// Reports whether the network is usable, so queued bookings go out once it is back (DO-26).
public enum NetworkMonitor {
    /// `true` whenever a usable path appears, `false` when it goes away.
    public static func changes() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.yield(path.status == .satisfied)
            }
            monitor.start(queue: DispatchQueue(label: "de.nilslutz.takt.network"))
            continuation.onTermination = { _ in monitor.cancel() }
        }
    }
}
