import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

@MainActor
struct CorrectionReasonTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    testDefaults = try TestDefaults("takt-correction")
    settings = AppSettings(defaults: testDefaults.defaults)
    let engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    model = MainWindowModel(
      engine: engine,
      queries: EntryQueries(database: database),
      catalog: CatalogModel(store: CatalogStore(database: database), clock: clock),
      settings: settings,
      database: database,
      clock: clock,
    )
  }

  // MARK: Internal

  @Test
  func changesToOldTimesWaitForTheReason() async throws {
    settings.askCorrectionReason = true
    model.step(by: -10)
    let start = model.dayRange.lowerBound.adding(seconds: 9 * 3600)
    let create = Task { await model.createEntry(from: start, to: start.adding(seconds: 3600)) }
    while model.correctionReasonRequest == nil {
      await Task.yield()
    }

    model.answerCorrectionReason("Forgot the timer")

    let id = try #require(await create.value)
    #expect(await model.corrections(of: id).first?.reason == "Forgot the timer")
  }

  @Test
  func skippingSavesWithoutAReason() async throws {
    settings.askCorrectionReason = true
    model.step(by: -10)
    let start = model.dayRange.lowerBound.adding(seconds: 9 * 3600)
    let create = Task { await model.createEntry(from: start, to: start.adding(seconds: 3600)) }
    while model.correctionReasonRequest == nil {
      await Task.yield()
    }

    model.answerCorrectionReason("  ")

    let id = try #require(await create.value)
    let records = await model.corrections(of: id)
    #expect(records.count == 1)
    #expect(records.first?.reason == nil)
  }

  @Test
  func recentChangesDoNotAsk() async throws {
    settings.askCorrectionReason = true
    let id = try #require(await model.createEntry(
      from: clock.now().adding(seconds: -7200),
      to: clock.now().adding(seconds: -3600),
    ))

    #expect(model.correctionReasonRequest == nil)
    #expect(await model.corrections(of: id).map(\.kind) == [.created])
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000))
  private let database: AppDatabase
  private let testDefaults: TestDefaults
  private let settings: AppSettings
  private let model: MainWindowModel
}
