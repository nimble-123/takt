import Foundation
import Observation
import TaktCore

/// User settings in `UserDefaults`. A configuration profile (MDM) can force values; those are
/// read-only in the UI (TECHNICAL_CONCEPT "Verwaltete Einstellungen").
@MainActor
@Observable
public final class AppSettings {
    public enum Key: String, CaseIterable, Sendable {
        case startMode, countingMode, idleThresholdMinutes, lockCountsAsPause, roundingMinutes
        case bookingMode, dailyGoalHours, showElapsedInMenuBar, onboardingCompleted
        case reduceRemainingWork, bookingIncludesNote, weeklyHours, workDays, gitFolders
    }

    /// When booked time goes to Azure DevOps (DO-21).
    public enum BookingMode: String, CaseIterable, Sendable {
        case manual, review, automatic
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Enter starts with this mode; ⌥↩ with the other (TM-05).
    public var startMode: TimerEngine.StartMode {
        didSet { write(.startMode, startMode == .parallel ? "parallel" : "switch") }
    }
    /// Default for entries without their own counting mode (TM-04).
    public var countingMode: CountingMode {
        didSet { write(.countingMode, countingMode.rawValue) }
    }
    public var idleThresholdMinutes: Int {
        didSet { write(.idleThresholdMinutes, idleThresholdMinutes) }
    }
    public var lockCountsAsPause: Bool {
        didSet { write(.lockCountsAsPause, lockCountsAsPause) }
    }
    /// 0 = no rounding; applies to export and Azure DevOps only (TM-10).
    public var roundingMinutes: Int {
        didSet { write(.roundingMinutes, roundingMinutes) }
    }
    public var bookingMode: BookingMode {
        didSet { write(.bookingMode, bookingMode.rawValue) }
    }
    public var dailyGoalHours: Double {
        didSet { write(.dailyGoalHours, dailyGoalHours) }
    }
    public var showElapsedInMenuBar: Bool {
        didSet { write(.showElapsedInMenuBar, showElapsedInMenuBar) }
    }
    public var onboardingCompleted: Bool {
        didSet { write(.onboardingCompleted, onboardingCompleted) }
    }
    /// AN-07: contractual hours per week for the target/actual comparison.
    public var weeklyHours: Double {
        didSet { write(.weeklyHours, weeklyHours) }
    }
    /// AN-07: working days, 1 = Monday … 7 = Sunday.
    public var workDays: Set<Int> {
        didSet { write(.workDays, workDays.sorted()) }
    }
    /// Folders whose Git repositories suggest work items by branch name.
    public var gitFolders: [String] {
        didSet { write(.gitFolders, gitFolders) }
    }
    /// DO-22: reduce Remaining Work by the booked time (never below 0).
    public var reduceRemainingWork: Bool {
        didSet { write(.reduceRemainingWork, reduceRemainingWork) }
    }
    /// DO-23: add the entry's note to the comment on the work item.
    public var bookingIncludesNote: Bool {
        didSet { write(.bookingIncludesNote, bookingIncludesNote) }
    }

    public static let roundingChoices = [0, 5, 6, 10, 15, 30]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        startMode = defaults.string(forKey: Key.startMode.rawValue) == "parallel" ? .parallel : .switchTo
        countingMode = defaults.string(forKey: Key.countingMode.rawValue).flatMap(CountingMode.init) ?? .split
        idleThresholdMinutes = max(1, defaults.object(forKey: Key.idleThresholdMinutes.rawValue) as? Int ?? 10)
        lockCountsAsPause = defaults.bool(forKey: Key.lockCountsAsPause.rawValue)
        roundingMinutes = max(0, defaults.integer(forKey: Key.roundingMinutes.rawValue))
        bookingMode = defaults.string(forKey: Key.bookingMode.rawValue).flatMap(BookingMode.init) ?? .review
        dailyGoalHours = defaults.object(forKey: Key.dailyGoalHours.rawValue) as? Double ?? 8
        showElapsedInMenuBar = defaults.object(forKey: Key.showElapsedInMenuBar.rawValue) as? Bool ?? true
        onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted.rawValue)
        reduceRemainingWork = defaults.object(forKey: Key.reduceRemainingWork.rawValue) as? Bool ?? true
        bookingIncludesNote = defaults.object(forKey: Key.bookingIncludesNote.rawValue) as? Bool ?? true
        weeklyHours = defaults.object(forKey: Key.weeklyHours.rawValue) as? Double ?? 40
        workDays = Set(defaults.array(forKey: Key.workDays.rawValue) as? [Int] ?? [1, 2, 3, 4, 5])
        gitFolders = defaults.stringArray(forKey: Key.gitFolders.rawValue) ?? []
    }

    /// Whether a configuration profile sets this value.
    public func isLocked(_ key: Key) -> Bool {
        defaults.objectIsForced(forKey: key.rawValue)
    }

    public var dailyGoal: TimeInterval { dailyGoalHours * 3600 }

    private func write(_ key: Key, _ value: Any) {
        guard !isLocked(key) else { return }
        defaults.set(value, forKey: key.rawValue)
    }
}
