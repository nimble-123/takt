import Foundation
import TaktCore

/// A system signal that interrupts work.
public enum SystemEvent: Sendable, Equatable {
    case willSleep, didWake, screenLocked, screenUnlocked
}

/// Signals about the user's presence. Faked in tests, so no test waits for real time.
public protocol ActivitySignals: Sendable {
    /// Seconds since the last keyboard, mouse or trackpad input.
    func secondsSinceLastInput() async -> TimeInterval
    /// Sleep, wake, lock and unlock as they happen.
    func events() -> AsyncStream<SystemEvent>
}

public struct IdleSettings: Sendable, Equatable {
    /// Shorter interruptions count as work (TM-06, default 10 min).
    public var threshold: TimeInterval
    /// Treat a locked screen as a pause without asking.
    public var lockCountsAsPause: Bool

    public init(threshold: TimeInterval = 600, lockCountsAsPause: Bool = false) {
        self.threshold = threshold
        self.lockCountsAsPause = lockCountsAsPause
    }
}

/// Detects inactivity while a timer runs and records it in the engine when the user returns
/// (TM-06, TM-07). Idle input is polled; sleep and lock arrive as events.
public actor IdleMonitor {
    private enum Cause { case input, sleep, lock }

    private let engine: TimerEngine
    private let signals: any ActivitySignals
    private let clock: any TaktClock
    private let settings: @Sendable () -> IdleSettings
    private var awaySince: Timestamp?
    private var cause: Cause?
    private let continuation: AsyncStream<IdleEvent>.Continuation

    /// Idle events that need the user's decision; the app shows the dialog for each.
    public nonisolated let returns: AsyncStream<IdleEvent>

    public static let pollInterval: Duration = .seconds(30)

    public init(
        engine: TimerEngine,
        signals: any ActivitySignals,
        clock: any TaktClock,
        settings: @escaping @Sendable () -> IdleSettings
    ) {
        self.engine = engine
        self.signals = signals
        self.clock = clock
        self.settings = settings
        (returns, continuation) = AsyncStream.makeStream(of: IdleEvent.self)
    }

    /// Polls and listens until the task is cancelled.
    public func run() async {
        let events = signals.events()
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await event in events {
                    await self.handle(event)
                }
            }
            group.addTask {
                while !Task.isCancelled {
                    await self.poll()
                    try? await Task.sleep(for: Self.pollInterval)
                }
            }
        }
    }

    /// Checks the input idle time. Only runs the check while a timer runs.
    public func poll() async {
        let idle = await signals.secondsSinceLastInput()
        let now = clock.now()
        let threshold = settings().threshold
        if let awaySince, cause == .input {
            if idle < threshold {
                await record(from: awaySince, to: now.adding(seconds: -idle), cause: .input)
            }
        } else if awaySince == nil, idle >= threshold, await isRunning() {
            awaySince = now.adding(seconds: -idle)
            cause = .input
        }
    }

    public func handle(_ event: SystemEvent) async {
        let now = clock.now()
        switch event {
        case .willSleep, .screenLocked:
            guard await isRunning() || awaySince != nil else { return }
            // Input idle may have started earlier; keep the earliest start.
            if awaySince == nil { awaySince = now }
            if cause != .sleep { cause = event == .willSleep ? .sleep : .lock }
        case .didWake, .screenUnlocked:
            guard let awaySince, cause == .sleep || cause == .lock else { return }
            if now.seconds(since: awaySince) >= settings().threshold {
                await record(from: awaySince, to: now, cause: cause ?? .lock)
            } else {
                // A short interruption counts as work.
                reset()
            }
        }
    }

    private func record(from start: Timestamp, to end: Timestamp, cause: Cause) async {
        reset()
        do {
            guard let event = try await engine.recordIdle(from: start, to: end) else { return }
            if cause == .lock, settings().lockCountsAsPause {
                try await engine.resolveIdle(event.id, .pause)
            } else {
                continuation.yield(event)
            }
        } catch {
            // The engine keeps its state; the next poll starts over.
        }
    }

    private func reset() {
        awaySince = nil
        cause = nil
    }

    private func isRunning() async -> Bool {
        (try? await engine.snapshot().running.isEmpty == false) ?? false
    }
}
