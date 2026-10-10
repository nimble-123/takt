import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

/// Settings → Data → "Reset to Factory Settings …".
@MainActor
struct FactoryResetTests {

  @Test
  func resetDeletesAllDataAndSettingsButKeepsTheSchema() async throws {
    let testDefaults = try TestDefaults("takt-reset")
    let database = try AppDatabase.inMemory()
    let clock = ManualClock()
    let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    try await CatalogStore(database: database).save(EntryCategory(name: "Meeting", color: "#C2410C"))
    let id = try await engine.start(EntryDraft(title: "A"), mode: .switchTo).value
    clock.advance(seconds: 60)
    try await engine.stop(id)
    try await AbsenceStore(database: database).set(.vacation, on: "2026-10-05")
    let settings = AppSettings(defaults: testDefaults.defaults)
    settings.weeklyHours = 38
    settings.onboardingCompleted = true
    var loginItemDisabled = false

    try await FactoryReset.run(
      database: database,
      azureDevOps: nil,
      defaults: testDefaults.defaults,
      domain: testDefaults.suiteName,
      disableLoginItem: { loginItemDisabled = true },
    )

    let counts = try await database.writer.read { db in
      try ["time_entry", "segment", "category", "absence"].map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") }
    }
    #expect(counts == [0, 0, 0, 0])
    #expect(try await EntryQueries(database: database).entries([id]).isEmpty)
    #expect(testDefaults.defaults.object(forKey: "weeklyHours") == nil)
    #expect(!AppSettings(defaults: testDefaults.defaults).onboardingCompleted)
    #expect(loginItemDisabled)
    // The schema stays: the app can write again at once.
    try await CatalogStore(database: database).save(EntryCategory(name: "Meeting", color: "#C2410C"))
  }
}
