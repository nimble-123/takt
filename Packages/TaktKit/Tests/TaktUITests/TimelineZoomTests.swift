import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

// MARK: - TimelineZoomTests

@MainActor
struct TimelineZoomTests {

  // MARK: Lifecycle

  init() throws {
    testDefaults = try TestDefaults("takt-zoom")
  }

  // MARK: Internal

  @Test
  func stepsGoToTheNextStepAndStopAtTheEnds() {
    #expect(TimelineZoom.step(56, by: 1) == 80)
    #expect(TimelineZoom.step(56, by: -1) == 40)
    // A pinch may stop between steps.
    #expect(TimelineZoom.step(60, by: 1) == 80)
    #expect(TimelineZoom.step(60, by: -1) == 56)
    #expect(TimelineZoom.step(160, by: 1) == 160)
    #expect(TimelineZoom.step(24, by: -2) == 24)
  }

  @Test
  func todayAndWeekZoomSeparately() throws {
    let model = try makeModel()

    model.zoom(by: 1)
    model.open(.week)
    model.zoom(by: -1)

    #expect(model.hourHeight(in: .today) == 80)
    #expect(model.hourHeight(in: .week) == 32)
  }

  @Test
  func resetGoesBackToTheStandard() throws {
    let model = try makeModel()
    model.zoom(by: 2)

    model.resetZoom()

    #expect(model.hourHeight(in: .today) == 56)
  }

  @Test
  func pinchingIsLimitedToTheSteps() throws {
    let model = try makeModel()

    model.setHourHeight(1000)

    #expect(model.hourHeight(in: .today) == 160)
  }

  @Test
  func theZoomIsKeptForTheNextLaunch() throws {
    try makeModel().zoom(by: 1)

    #expect(try makeModel().hourHeight(in: .today) == 80)
  }

  @Test
  func screensWithoutATimelineDoNotZoom() throws {
    let model = try makeModel()
    model.open(.entries)

    model.zoom(by: 1)

    #expect(!model.canZoom)
    #expect(model.hourHeight(in: .today) == 56)
    #expect(model.hourHeight(in: .week) == 40)
  }

  // MARK: Private

  private let testDefaults: TestDefaults

  private func makeModel() throws -> MainWindowModel {
    let database = try AppDatabase.inMemory()
    let clock = ManualClock(Timestamp(milliseconds: 1_791_878_400_000))
    return MainWindowModel(
      engine: TimerEngine(store: GRDBTimerStore(database: database), clock: clock),
      queries: EntryQueries(database: database),
      catalog: CatalogModel(store: CatalogStore(database: database), clock: clock),
      zoomDefaults: testDefaults.defaults,
      clock: clock,
    )
  }
}
