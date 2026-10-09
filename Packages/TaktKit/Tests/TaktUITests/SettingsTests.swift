import Foundation
import TaktAnalytics
import TaktCore
import TaktStore
import TaktSystem
import Testing

@testable import TaktUI

@MainActor
struct SettingsTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults("takt-settings")
  }

  // MARK: Internal

  @Test
  func defaultsMatchThePRD() {
    let settings = AppSettings(defaults: defaults())
    #expect(settings.startMode == .switchTo)
    #expect(settings.countingMode == .split)
    #expect(settings.idleThresholdMinutes == 10)
    #expect(settings.roundingMinutes == 0)
    #expect(settings.bookingMode == .review)
    #expect(settings.dailyGoal == 8 * 3600)
    #expect(settings.showElapsedInMenuBar)
    #expect(!settings.onboardingCompleted)
    #expect(settings.noTimerReminder == NoTimerReminderSettings())
    #expect(settings.federalState == nil)
  }

  @Test
  func changesArePersistedUnderTheKeysOtherModulesRead() {
    let store = defaults()
    let settings = AppSettings(defaults: store)
    settings.startMode = .parallel
    settings.countingMode = .full
    settings.idleThresholdMinutes = 15
    settings.roundingMinutes = 15
    settings.bookingMode = .automatic

    #expect(store.string(forKey: "startMode") == "parallel")
    #expect(store.string(forKey: "countingMode") == "full")
    #expect(store.integer(forKey: "idleThresholdMinutes") == 15)
    #expect(store.integer(forKey: "roundingMinutes") == 15)
    #expect(store.string(forKey: "bookingMode") == "automatic")

    let reloaded = AppSettings(defaults: store)
    #expect(reloaded.startMode == .parallel)
    #expect(reloaded.countingMode == .full)
  }

  @Test
  func snapshotForTheServicesFollowsEveryChange() {
    let settings = AppSettings(defaults: defaults())
    #expect(settings.snapshot.idle == IdleSettings(threshold: 600, lockCountsAsPause: false))
    #expect(settings.snapshot.bookingOptions.reduceRemainingWork)
    #expect(settings.snapshot.bookingOptions.includeNote)

    settings.idleThresholdMinutes = 15
    settings.lockCountsAsPause = true
    settings.reduceRemainingWork = false
    settings.bookingIncludesNote = false
    settings.gitFolders = ["/Users/x/src"]

    let snapshot = settings.snapshot
    #expect(snapshot.idle == IdleSettings(threshold: 900, lockCountsAsPause: true))
    #expect(!snapshot.bookingOptions.reduceRemainingWork)
    #expect(!snapshot.bookingOptions.includeNote)
    #expect(snapshot.gitBranches.folders == [URL(filePath: "/Users/x/src")])
    #expect(AppSettings(defaults: defaults()).snapshot == snapshot)
  }

  @Test
  func analyticsReadTargetRoundingAndCountingModeFromTheSettings() throws {
    let settings = AppSettings(defaults: defaults())
    settings.weeklyHours = 32
    settings.workDays = [1, 2, 3, 4]
    settings.roundingMinutes = 15
    settings.countingMode = .full
    let model = AnalyticsModel(
      source: AnalyticsSource(database: try AppDatabase.inMemory()),
      settings: settings,
      clock: ManualClock(),
    )

    #expect(model.targetPlan == TargetPlan(weeklyHours: 32, workDays: [1, 2, 3, 4]))
    #expect(model.rounding == Rounding(minutes: 15))
    #expect(model.defaultMode == .full)
  }

  @Test
  func onboardingWalksThreeStepsAndFinishes() {
    let settings = AppSettings(defaults: defaults())
    let model = OnboardingModel(settings: settings)
    model.launchAtLogin = false
    var finished = false
    model.onFinish = { finished = true }

    model.shortcutPressed()
    #expect(!model.shortcutTested) // only counts in the shortcut step
    model.next()
    #expect(model.step == .shortcut)
    model.shortcutPressed()
    #expect(model.shortcutTested)
    model.next()
    #expect(model.step == .behaviour)
    model.next()

    #expect(finished)
    #expect(settings.onboardingCompleted)
  }

  @Test
  func hoursKeepTenthsAndStayInRange() {
    let settings = AppSettings(defaults: defaults())
    settings.dailyGoalHours = 7.6
    #expect(settings.dailyGoalHours == 7.6)
    settings.dailyGoalHours = 7.649
    #expect(settings.dailyGoalHours == 7.6)
    settings.dailyGoalHours = 20
    #expect(settings.dailyGoalHours == 12)
    settings.weeklyHours = 38.56
    #expect(settings.weeklyHours == 38.6)
    settings.weeklyHours = -1
    #expect(settings.weeklyHours == 0)
  }

  @Test
  func repeatedStepsLeaveNoRemainder() {
    let settings = AppSettings(defaults: defaults())
    settings.dailyGoalHours = 7
    for _ in 0..<6 { settings.dailyGoalHours += 0.1 }
    #expect(settings.dailyGoalHours == 7.6)
    #expect(defaults().double(forKey: AppSettings.Key.dailyGoalHours.rawValue) == 7.6)
  }

  @Test
  func dailyGoalIsSuggestedFromWeeklyHours() {
    let settings = AppSettings(defaults: defaults())
    settings.weeklyHours = 38
    settings.workDays = [1, 2, 3, 4, 5]
    #expect(settings.suggestedDailyGoalHours == 7.6)
    settings.workDays = []
    #expect(settings.suggestedDailyGoalHours == nil)
  }

  @Test
  func managedValuesKeepTheirDecimals() {
    let store = defaults()
    store.set(7.75, forKey: AppSettings.Key.dailyGoalHours.rawValue)
    let settings = AppSettings(defaults: store) { $0 == AppSettings.Key.dailyGoalHours.rawValue }
    #expect(settings.dailyGoalHours == 7.75)
    #expect(settings.isLocked(.dailyGoalHours))
  }

  // MARK: Private

  private let testDefaults: TestDefaults

  private func defaults() -> UserDefaults {
    testDefaults.defaults
  }

}
