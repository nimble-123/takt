import Foundation
import TaktCore
import Testing

@testable import TaktUI

@MainActor
struct SettingsTests {
    let suite = "takt-settings-\(UUID().uuidString)"

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: suite) ?? .standard
    }

    @Test func defaultsMatchThePRD() {
        let settings = AppSettings(defaults: defaults())
        #expect(settings.startMode == .switchTo)
        #expect(settings.countingMode == .split)
        #expect(settings.idleThresholdMinutes == 10)
        #expect(settings.roundingMinutes == 0)
        #expect(settings.bookingMode == .review)
        #expect(settings.dailyGoal == 8 * 3600)
        #expect(settings.showElapsedInMenuBar)
        #expect(!settings.onboardingCompleted)
    }

    @Test func changesArePersistedUnderTheKeysOtherModulesRead() {
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

    @Test func onboardingWalksThreeStepsAndFinishes() {
        let settings = AppSettings(defaults: defaults())
        let model = OnboardingModel(settings: settings)
        model.launchAtLogin = false
        var finished = false
        model.onFinish = { finished = true }

        model.shortcutPressed()
        #expect(!model.shortcutTested)  // only counts in the shortcut step
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

    @Test func hoursKeepTenthsAndStayInRange() {
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

    @Test func repeatedStepsLeaveNoRemainder() {
        let settings = AppSettings(defaults: defaults())
        settings.dailyGoalHours = 7
        for _ in 0..<6 { settings.dailyGoalHours += 0.1 }
        #expect(settings.dailyGoalHours == 7.6)
        #expect(defaults().double(forKey: AppSettings.Key.dailyGoalHours.rawValue) == 7.6)
    }

    @Test func dailyGoalIsSuggestedFromWeeklyHours() {
        let settings = AppSettings(defaults: defaults())
        settings.weeklyHours = 38
        settings.workDays = [1, 2, 3, 4, 5]
        #expect(settings.suggestedDailyGoalHours == 7.6)
        settings.workDays = []
        #expect(settings.suggestedDailyGoalHours == nil)
    }

    @Test func managedValuesKeepTheirDecimals() {
        let store = defaults()
        store.set(7.75, forKey: AppSettings.Key.dailyGoalHours.rawValue)
        let settings = AppSettings(defaults: store) { $0 == AppSettings.Key.dailyGoalHours.rawValue }
        #expect(settings.dailyGoalHours == 7.75)
        #expect(settings.isLocked(.dailyGoalHours))
    }
}
