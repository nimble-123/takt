import Foundation
import Observation
import os
import TaktADO
import TaktAnalytics
import TaktCore
import TaktSystem

/// User settings in `UserDefaults`. A configuration profile (MDM) can force values; those are
/// read-only in the UI (TECHNICAL_CONCEPT "Verwaltete Einstellungen").
@Observable
public final class AppSettings {

  // MARK: Lifecycle

  public init(defaults: UserDefaults = .standard, isForced: ((String) -> Bool)? = nil) {
    self.defaults = defaults
    self.isForced = isForced ?? { defaults.objectIsForced(forKey: $0) }
    let snapshot = Snapshot(
      idleThresholdMinutes: max(1, defaults.object(forKey: Key.idleThresholdMinutes.rawValue) as? Int ?? 10),
      lockCountsAsPause: defaults.bool(forKey: Key.lockCountsAsPause.rawValue),
      reduceRemainingWork: defaults.object(forKey: Key.reduceRemainingWork.rawValue) as? Bool ?? true,
      bookingIncludesNote: defaults.object(forKey: Key.bookingIncludesNote.rawValue) as? Bool ?? true,
      gitFolders: defaults.stringArray(forKey: Key.gitFolders.rawValue) ?? [],
    )
    snapshotLock = OSAllocatedUnfairLock(initialState: snapshot)
    startMode = defaults.string(forKey: Key.startMode.rawValue) == "parallel" ? .parallel : .switchTo
    countingMode = defaults.string(forKey: Key.countingMode.rawValue).flatMap(CountingMode.init) ?? .split
    idleThresholdMinutes = snapshot.idleThresholdMinutes
    lockCountsAsPause = snapshot.lockCountsAsPause
    roundingMinutes = max(0, defaults.integer(forKey: Key.roundingMinutes.rawValue))
    bookingMode = defaults.string(forKey: Key.bookingMode.rawValue).flatMap(BookingMode.init) ?? .review
    dailyGoalHours = defaults.object(forKey: Key.dailyGoalHours.rawValue) as? Double ?? 8
    showElapsedInMenuBar = defaults.object(forKey: Key.showElapsedInMenuBar.rawValue) as? Bool ?? true
    onboardingCompleted = defaults.bool(forKey: Key.onboardingCompleted.rawValue)
    reduceRemainingWork = snapshot.reduceRemainingWork
    bookingIncludesNote = snapshot.bookingIncludesNote
    weeklyHours = defaults.object(forKey: Key.weeklyHours.rawValue) as? Double ?? 40
    workDays = Set(defaults.array(forKey: Key.workDays.rawValue) as? [Int] ?? [1, 2, 3, 4, 5])
    gitFolders = snapshot.gitFolders
  }

  // MARK: Public

  public enum Key: String, CaseIterable, Sendable {
    case startMode
    case countingMode
    case idleThresholdMinutes
    case lockCountsAsPause
    case roundingMinutes
    case bookingMode
    case dailyGoalHours
    case showElapsedInMenuBar
    case onboardingCompleted
    case reduceRemainingWork
    case bookingIncludesNote
    case weeklyHours
    case workDays
    case gitFolders
  }

  /// When booked time goes to Azure DevOps (DO-21).
  public enum BookingMode: String, CaseIterable, Sendable {
    case manual
    case review
    case automatic
  }

  /// The settings that services read outside the main actor (idle monitor, booking service, Git
  /// branches); a copy that follows every change.
  nonisolated public struct Snapshot: Sendable, Equatable {
    public var idleThresholdMinutes: Int
    public var lockCountsAsPause: Bool
    public var reduceRemainingWork: Bool
    public var bookingIncludesNote: Bool
    public var gitFolders: [String]

    public var idle: IdleSettings {
      IdleSettings(threshold: TimeInterval(idleThresholdMinutes * 60), lockCountsAsPause: lockCountsAsPause)
    }

    /// DO-22, DO-23.
    public var bookingOptions: BookingService.Options {
      BookingService.Options(reduceRemainingWork: reduceRemainingWork, includeNote: bookingIncludesNote)
    }

    public var gitBranches: GitBranches {
      GitBranches(folders: gitFolders.map { URL(filePath: $0) })
    }
  }

  public static let roundingChoices = [0, 5, 6, 10, 15, 30]
  public static let dailyGoalRange: ClosedRange<Double> = 1...12
  public static let weeklyHoursRange: ClosedRange<Double> = 0...60

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

  /// MB-08; kept at 0.1 h steps within `dailyGoalRange`, e.g. 7.6 h for a 38-hour week.
  public var dailyGoalHours: Double {
    didSet {
      let hours = Self.hours(dailyGoalHours, in: Self.dailyGoalRange)
      if hours != dailyGoalHours { dailyGoalHours = hours }
      write(.dailyGoalHours, dailyGoalHours)
    }
  }

  public var showElapsedInMenuBar: Bool {
    didSet { write(.showElapsedInMenuBar, showElapsedInMenuBar) }
  }

  public var onboardingCompleted: Bool {
    didSet { write(.onboardingCompleted, onboardingCompleted) }
  }

  /// AN-07: contractual hours per week for the target/actual comparison.
  public var weeklyHours: Double {
    didSet {
      let hours = Self.hours(weeklyHours, in: Self.weeklyHoursRange)
      if hours != weeklyHours { weeklyHours = hours }
      write(.weeklyHours, weeklyHours)
    }
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

  /// Readable from any isolation, e.g. from the `@Sendable` closures of the services.
  public nonisolated var snapshot: Snapshot {
    snapshotLock.withLock { $0 }
  }

  /// AN-07: the weekly hours spread over the working days.
  public var targetPlan: TargetPlan {
    TargetPlan(weeklyHours: weeklyHours, workDays: workDays)
  }

  public var rounding: Rounding {
    Rounding(minutes: roundingMinutes)
  }

  public var dailyGoal: TimeInterval {
    dailyGoalHours * 3600
  }

  /// The weekly hours spread over the working days, e.g. 38 h ÷ 5 = 7.6 h; `nil` without working days.
  public var suggestedDailyGoalHours: Double? {
    guard !workDays.isEmpty else { return nil }
    return Self.hours(weeklyHours / Double(workDays.count), in: Self.dailyGoalRange)
  }

  /// Hours as the settings keep them: rounded to 0.1 h, so repeated steps leave no
  /// floating-point remainders, and clamped to `range`.
  public static func hours(_ value: Double, in range: ClosedRange<Double>) -> Double {
    guard value.isFinite else { return range.lowerBound }
    return min(max((value * 10).rounded() / 10, range.lowerBound), range.upperBound)
  }

  /// Whether a configuration profile sets this value.
  public func isLocked(_ key: Key) -> Bool {
    isForced(key.rawValue)
  }

  // MARK: Private

  @ObservationIgnored private let defaults: UserDefaults
  /// Whether a configuration profile sets a key; replaceable in tests.
  @ObservationIgnored private let isForced: (String) -> Bool
  @ObservationIgnored private nonisolated let snapshotLock: OSAllocatedUnfairLock<Snapshot>

  private func write(_ key: Key, _ value: Any) {
    let snapshot = Snapshot(
      idleThresholdMinutes: idleThresholdMinutes,
      lockCountsAsPause: lockCountsAsPause,
      reduceRemainingWork: reduceRemainingWork,
      bookingIncludesNote: bookingIncludesNote,
      gitFolders: gitFolders,
    )
    snapshotLock.withLock { $0 = snapshot }
    guard !isLocked(key) else { return }
    defaults.set(value, forKey: key.rawValue)
  }
}
