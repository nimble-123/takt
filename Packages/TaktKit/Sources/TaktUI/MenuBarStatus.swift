import Foundation
import TaktCore

/// What the status item shows for a timer state (MB-01).
public struct MenuBarStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle, running, paused
    }

    public var state: State
    /// Running time of the newest running entry as `h:mm`, if any.
    public var title: String?

    public init(snapshot: TimerSnapshot, now: Timestamp) {
        if let newest = snapshot.running.max(by: { $0.entry.createdAt < $1.entry.createdAt }) {
            state = .running
            title = DurationText.hoursMinutes(newest.elapsed(at: now))
        } else {
            state = snapshot.paused.isEmpty ? .idle : .paused
            title = nil
        }
    }

    /// SF Symbol shown as a template image.
    public var symbolName: String {
        switch state {
        case .idle: "stopwatch"
        case .running: "stopwatch.fill"
        case .paused: "pause.circle"
        }
    }
}

/// Durations as shown in the UI. Times use tabular digits in the views.
public enum DurationText {
    /// `0:07`, `1:05` – menu bar and totals.
    public static func hoursMinutes(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        return "\(minutes / 60):\(pad(minutes % 60))"
    }

    /// `24 min`, `1 h 05 min` – spans in sentences.
    public static func span(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(0, seconds) / 60).rounded())
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(pad(minutes % 60)) min"
    }

    /// `0:07:09`, `12:05:00` – live time in the popover.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        return "\(total / 3600):\(pad(total / 60 % 60)):\(pad(total % 60))"
    }

    private static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
