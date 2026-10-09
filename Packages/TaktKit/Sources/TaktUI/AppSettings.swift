import Foundation
import Observation
import os
import TaktADO
import TaktAnalytics
import TaktCore
import TaktSystem

// MARK: - AppSettings

/// User settings in `UserDefaults`. A configuration profile (MDM) can force values; those are
/// read-only in the UI (TECHNICAL_CONCEPT "Verwaltete Einstellungen").
@Observable
public final class AppSettings {

  // MARK: Lifecycle

  public init(defaults: UserDefaults = .standard, isForced: ((String) -> Bool)? = nil) {
    self.defaults = defaults
    self.isForced = isForced ?? { defaults.objectIsForced(forKey: $0) }
    let stored = Stored(defaults)
    let snapshot = Snapshot(
      idleThresholdMinutes: stored.idleThresholdMinutes,
      lockCountsAsPause: stored.lockCountsAsPause,
      reduceRemainingWork: stored.reduceRemainingWork,
      bookingIncludesNote: stored.bookingIncludesNote,
      gitFolders: stored.gitFolders,
    )
    snapshotLock = OSAllocatedUnfairLock(initialState: snapshot)
    startMode = stored.startMode
    countingMode = stored.countingMode
    idleThresholdMinutes = stored.idleThresholdMinutes
    lockCountsAsPause = stored.lockCountsAsPause
    roundingMinutes = stored.roundingMinutes
    bookingMode = stored.bookingMode
    dailyGoalHours = stored.dailyGoalHours
    showElapsedInMenuBar = stored.showElapsedInMenuBar
    onboardingCompleted = stored.onboardingCompleted
    reduceRemainingWork = stored.reduceRemainingWork
    bookingIncludesNote = stored.bookingIncludesNote
    weeklyHours = stored.weeklyHours
    workDays = stored.workDays
    gitFolders = stored.gitFolders
    remindWhenNoTimer = stored.remindWhenNoTimer
    noTimerReminderMinutes = stored.noTimerReminderMinutes
    workdayStartMinute = stored.workdayStartMinute
    workdayEndMinute = stored.workdayEndMinute
    federalState = stored.federalState
    askCorrectionReason = stored.askCorrectionReason
    workTimeModel = stored.workTimeModel
    flexStartBalanceHours = stored.flexStartBalanceHours
    flexStartDay = stored.flexStartDay
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
    case remindWhenNoTimer
    case noTimerReminderMinutes
    case workdayStartMinute
    case workdayEndMinute
    case federalState
    case askCorrectionReason
    case workTimeModel
    case flexStartBalanceHours
    case flexStartDay
  }

  /// AZ-05: flex time keeps a target and the flex account; trust-based working time hides both.
  public enum WorkTimeModel: String, CaseIterable, Sendable {
    case flexTime
    case trust
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
  public static let noTimerReminderRange = 5...120
  public static let flexStartBalanceRange: ClosedRange<Double> = -999...999

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
      // A profile's value is kept as it is, e.g. 7.75 h.
      let hours = Self.hours(dailyGoalHours, in: Self.dailyGoalRange)
      if hours != dailyGoalHours, !isLocked(.dailyGoalHours) { dailyGoalHours = hours }
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
      if hours != weeklyHours, !isLocked(.weeklyHours) { weeklyHours = hours }
      write(.weeklyHours, weeklyHours)
    }
  }

  /// AN-07: working days, 1 = Monday … 7 = Sunday.
  public var workDays: Set<Int> {
    didSet { write(.workDays, workDays.sorted()) }
  }

  /// TM-09: remind during working hours when no timer runs.
  public var remindWhenNoTimer: Bool {
    didSet { write(.remindWhenNoTimer, remindWhenNoTimer) }
  }

  /// TM-09: minutes without a running timer before a reminder.
  public var noTimerReminderMinutes: Int {
    didSet { write(.noTimerReminderMinutes, noTimerReminderMinutes) }
  }

  /// TM-09: working hours as minutes after local midnight, e.g. 540 for 9:00.
  public var workdayStartMinute: Int {
    didSet { write(.workdayStartMinute, workdayStartMinute) }
  }

  public var workdayEndMinute: Int {
    didSet { write(.workdayEndMinute, workdayEndMinute) }
  }

  /// AZ-03: public holidays of this state have no target; `nil` = none.
  public var federalState: FederalState? {
    didSet { write(.federalState, federalState?.rawValue ?? "") }
  }

  /// AZ-04: ask for an optional reason when times older than 7 days change (§ 17 MiLoG).
  public var askCorrectionReason: Bool {
    didSet { write(.askCorrectionReason, askCorrectionReason) }
  }

  /// AZ-05: flex time (default) or trust-based working time.
  public var workTimeModel: WorkTimeModel {
    didSet { write(.workTimeModel, workTimeModel.rawValue) }
  }

  /// AZ-05: the flex account's balance before `flexStartDay`, e.g. carried over; may be negative.
  public var flexStartBalanceHours: Double {
    didSet {
      let hours = Self.hours(flexStartBalanceHours, in: Self.flexStartBalanceRange)
      if hours != flexStartBalanceHours, !isLocked(.flexStartBalanceHours) { flexStartBalanceHours = hours }
      write(.flexStartBalanceHours, flexStartBalanceHours)
    }
  }

  /// AZ-05: the first day the flex account counts, `YYYY-MM-DD`; `nil` = the first tracked day.
  public var flexStartDay: String? {
    didSet { write(.flexStartDay, flexStartDay ?? "") }
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
    TargetPlan(weeklyHours: weeklyHours, workDays: workDays, federalState: federalState)
  }

  public var noTimerReminder: NoTimerReminderSettings {
    NoTimerReminderSettings(
      isEnabled: remindWhenNoTimer,
      workDays: workDays,
      startMinute: workdayStartMinute,
      endMinute: workdayEndMinute,
      interval: TimeInterval(noTimerReminderMinutes * 60),
    )
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
    // A value set by a configuration profile wins, also for controls that do not check
    // `isLocked`, e.g. in the onboarding (#147).
    if isLocked(key) {
      restoreManagedValue(key)
    } else {
      defaults.set(value, forKey: key.rawValue)
    }
    let snapshot = Snapshot(
      idleThresholdMinutes: idleThresholdMinutes,
      lockCountsAsPause: lockCountsAsPause,
      reduceRemainingWork: reduceRemainingWork,
      bookingIncludesNote: bookingIncludesNote,
      gitFolders: gitFolders,
    )
    snapshotLock.withLock { $0 = snapshot }
  }

  /// Sets the property of a locked key back to the profile's value. Assigns only on a difference:
  /// the assignment calls `write` again, which then finds the values equal and stops.
  private func restoreManagedValue(_ key: Key) {
    let stored = Stored(defaults)
    switch key {
    case .startMode: if startMode != stored.startMode { startMode = stored.startMode }

    case .countingMode: if countingMode != stored.countingMode { countingMode = stored.countingMode }

    case .idleThresholdMinutes:
      if idleThresholdMinutes != stored.idleThresholdMinutes { idleThresholdMinutes = stored.idleThresholdMinutes }

    case .lockCountsAsPause:
      if lockCountsAsPause != stored.lockCountsAsPause { lockCountsAsPause = stored.lockCountsAsPause }

    case .roundingMinutes: if roundingMinutes != stored.roundingMinutes { roundingMinutes = stored.roundingMinutes }

    case .bookingMode: if bookingMode != stored.bookingMode { bookingMode = stored.bookingMode }

    case .dailyGoalHours: if dailyGoalHours != stored.dailyGoalHours { dailyGoalHours = stored.dailyGoalHours }

    case .showElapsedInMenuBar:
      if showElapsedInMenuBar != stored.showElapsedInMenuBar { showElapsedInMenuBar = stored.showElapsedInMenuBar }

    case .onboardingCompleted:
      if onboardingCompleted != stored.onboardingCompleted { onboardingCompleted = stored.onboardingCompleted }

    case .reduceRemainingWork:
      if reduceRemainingWork != stored.reduceRemainingWork { reduceRemainingWork = stored.reduceRemainingWork }

    case .bookingIncludesNote:
      if bookingIncludesNote != stored.bookingIncludesNote { bookingIncludesNote = stored.bookingIncludesNote }

    case .weeklyHours: if weeklyHours != stored.weeklyHours { weeklyHours = stored.weeklyHours }

    case .workDays: if workDays != stored.workDays { workDays = stored.workDays }

    case .gitFolders: if gitFolders != stored.gitFolders { gitFolders = stored.gitFolders }

    case .remindWhenNoTimer:
      if remindWhenNoTimer != stored.remindWhenNoTimer { remindWhenNoTimer = stored.remindWhenNoTimer }

    case .noTimerReminderMinutes:
      if noTimerReminderMinutes != stored.noTimerReminderMinutes {
        noTimerReminderMinutes = stored.noTimerReminderMinutes
      }

    case .workdayStartMinute:
      if workdayStartMinute != stored.workdayStartMinute { workdayStartMinute = stored.workdayStartMinute }

    case .workdayEndMinute:
      if workdayEndMinute != stored.workdayEndMinute { workdayEndMinute = stored.workdayEndMinute }

    case .federalState: if federalState != stored.federalState { federalState = stored.federalState }

    case .askCorrectionReason:
      if askCorrectionReason != stored.askCorrectionReason { askCorrectionReason = stored.askCorrectionReason }

    case .workTimeModel: if workTimeModel != stored.workTimeModel { workTimeModel = stored.workTimeModel }

    case .flexStartBalanceHours:
      if flexStartBalanceHours != stored.flexStartBalanceHours { flexStartBalanceHours = stored.flexStartBalanceHours }

    case .flexStartDay: if flexStartDay != stored.flexStartDay { flexStartDay = stored.flexStartDay }
    }
  }
}

// MARK: - Stored

/// The values as `UserDefaults` holds them, with a profile's values taking precedence.
private struct Stored {

  // MARK: Lifecycle

  init(_ defaults: UserDefaults) {
    startMode = defaults.string(forKey: AppSettings.Key.startMode.rawValue) == "parallel" ? .parallel : .switchTo
    countingMode = defaults.string(forKey: AppSettings.Key.countingMode.rawValue).flatMap(CountingMode.init) ?? .split
    idleThresholdMinutes = max(1, defaults.object(forKey: AppSettings.Key.idleThresholdMinutes.rawValue) as? Int ?? 10)
    lockCountsAsPause = defaults.bool(forKey: AppSettings.Key.lockCountsAsPause.rawValue)
    roundingMinutes = max(0, defaults.integer(forKey: AppSettings.Key.roundingMinutes.rawValue))
    bookingMode = defaults.string(forKey: AppSettings.Key.bookingMode.rawValue)
      .flatMap(AppSettings.BookingMode.init) ?? .review
    dailyGoalHours = defaults.object(forKey: AppSettings.Key.dailyGoalHours.rawValue) as? Double ?? 8
    showElapsedInMenuBar = defaults.object(forKey: AppSettings.Key.showElapsedInMenuBar.rawValue) as? Bool ?? true
    onboardingCompleted = defaults.bool(forKey: AppSettings.Key.onboardingCompleted.rawValue)
    reduceRemainingWork = defaults.object(forKey: AppSettings.Key.reduceRemainingWork.rawValue) as? Bool ?? true
    bookingIncludesNote = defaults.object(forKey: AppSettings.Key.bookingIncludesNote.rawValue) as? Bool ?? true
    weeklyHours = defaults.object(forKey: AppSettings.Key.weeklyHours.rawValue) as? Double ?? 40
    workDays = Set(defaults.array(forKey: AppSettings.Key.workDays.rawValue) as? [Int] ?? [1, 2, 3, 4, 5])
    gitFolders = defaults.stringArray(forKey: AppSettings.Key.gitFolders.rawValue) ?? []
    remindWhenNoTimer = defaults.object(forKey: AppSettings.Key.remindWhenNoTimer.rawValue) as? Bool ?? true
    let reminderMinutes = defaults.object(forKey: AppSettings.Key.noTimerReminderMinutes.rawValue) as? Int ?? 15
    noTimerReminderMinutes = max(1, reminderMinutes)
    workdayStartMinute = Self.minuteOfDay(defaults, .workdayStartMinute) ?? 9 * 60
    workdayEndMinute = Self.minuteOfDay(defaults, .workdayEndMinute) ?? 17 * 60
    federalState = defaults.string(forKey: AppSettings.Key.federalState.rawValue).flatMap(FederalState.init)
    askCorrectionReason = defaults.bool(forKey: AppSettings.Key.askCorrectionReason.rawValue)
    workTimeModel = defaults.string(forKey: AppSettings.Key.workTimeModel.rawValue)
      .flatMap(AppSettings.WorkTimeModel.init) ?? .flexTime
    flexStartBalanceHours = defaults.object(forKey: AppSettings.Key.flexStartBalanceHours.rawValue) as? Double ?? 0
    flexStartDay = defaults.string(forKey: AppSettings.Key.flexStartDay.rawValue)
      .flatMap { Timestamp.localDayParts($0) != nil ? $0 : nil }
  }

  // MARK: Internal

  let startMode: TimerEngine.StartMode
  let countingMode: CountingMode
  let idleThresholdMinutes: Int
  let lockCountsAsPause: Bool
  let roundingMinutes: Int
  let bookingMode: AppSettings.BookingMode
  let dailyGoalHours: Double
  let showElapsedInMenuBar: Bool
  let onboardingCompleted: Bool
  let reduceRemainingWork: Bool
  let bookingIncludesNote: Bool
  let weeklyHours: Double
  let workDays: Set<Int>
  let gitFolders: [String]
  let remindWhenNoTimer: Bool
  let noTimerReminderMinutes: Int
  let workdayStartMinute: Int
  let workdayEndMinute: Int
  let federalState: FederalState?
  let askCorrectionReason: Bool
  let workTimeModel: AppSettings.WorkTimeModel
  let flexStartBalanceHours: Double
  let flexStartDay: String?

  // MARK: Private

  /// A minute after midnight (0…1440); other values fall back to the default.
  private static func minuteOfDay(_ defaults: UserDefaults, _ key: AppSettings.Key) -> Int? {
    guard let minute = defaults.object(forKey: key.rawValue) as? Int, (0...1440).contains(minute) else { return nil }
    return minute
  }
}
