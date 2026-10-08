import Foundation
import TaktCore
import TaktStore
import Testing

@testable import TaktUI

// MARK: - FuzzyMatchTests

struct FuzzyMatchTests {
  @Test
  func charactersMustAppearInOrder() {
    #expect(FuzzyMatch.score("pse", in: "Pause All") != nil)
    #expect(FuzzyMatch.score("esp", in: "Pause All") == nil)
  }

  @Test
  func wordStartsAndRunsScoreHigher() throws {
    let wordStarts = try #require(FuzzyMatch.score("na", in: "New Entry … all"))
    let scattered = try #require(FuzzyMatch.score("na", in: "Show Analytics"))
    #expect(wordStarts > scattered)
    let run = try #require(FuzzyMatch.score("exp", in: "Export as CSV"))
    let spread = try #require(FuzzyMatch.score("exp", in: "Next day or Week, Pause"))
    #expect(run > spread)
  }

  @Test
  func caseAndUmlautsAreIgnored() {
    #expect(FuzzyMatch.score("einstellungen", in: "Show Einstellungen") != nil)
    #expect(FuzzyMatch.score("UBER", in: "Überblick") != nil)
  }
}

// MARK: - CommandPaletteTests

@MainActor
struct CommandPaletteTests {

  // MARK: Lifecycle

  init() throws {
    database = try AppDatabase.inMemory()
    engine = TimerEngine(store: GRDBTimerStore(database: database), clock: clock)
    window = MainWindowModel(
      engine: engine,
      queries: EntryQueries(database: database),
      catalog: CatalogModel(store: CatalogStore(database: database), clock: clock),
      search: SearchIndex(database: database),
      clock: clock,
    )
    palette = CommandPaletteModel(window: window)
  }

  // MARK: Internal

  @Test
  func emptyQueryListsAllActions() {
    palette.isPresented = true
    #expect(palette.items.contains { $0.id == "new-entry" && $0.shortcut == "⌘N" })
    #expect(palette.items.contains { $0.id == "section-week" })
  }

  @Test
  func typedTextCanStartATimer() async throws {
    palette.isPresented = true
    palette.query = "Kundentermin"
    palette.selection = try #require(palette.items.firstIndex { $0.id == "start-typed" })
    await palette.runSelected()

    #expect(!palette.isPresented)
    #expect(try await engine.snapshot().running.map(\.entry.title) == ["Kundentermin"])
  }

  @Test
  func actionsAreFoundFuzzily() {
    palette.query = "stp all"
    #expect(palette.items.first?.id == "stop-all")
  }

  @Test
  func pauseAllFromThePaletteIsUndoable() async throws {
    _ = try await engine.start(EntryDraft(title: "A"), mode: .switchTo)
    clock.advance(seconds: 60)
    palette.query = "pause"
    palette.selection = try #require(palette.items.firstIndex { $0.id == "pause-all" })
    await palette.runSelected()
    #expect(try await engine.snapshot().running.isEmpty)
  }

  @Test
  func entriesFromTheSearchAppearAsHits() async throws {
    let (entry, changes) = try EntryEdits.create(
      EntryDraft(title: "Quartalsplanung"),
      from: clock.now().adding(seconds: -7200),
      to: clock.now().adding(seconds: -3600),
      now: clock.now(),
    )
    try await engine.apply(changes)
    palette.query = "quartal"
    await palette.hitTask?.value
    #expect(palette.items.contains { $0.id == "entry-\(entry.id)" })
  }

  @Test
  func selectionWrapsAround() {
    let count = palette.items.count
    palette.moveSelection(by: -1)
    #expect(palette.selection == count - 1)
    palette.moveSelection(by: 1)
    #expect(palette.selection == 0)
  }

  // MARK: Private

  private let clock = ManualClock(Timestamp(milliseconds: 1_791_360_000_000))
  private let database: AppDatabase
  private let engine: TimerEngine
  private let window: MainWindowModel
  private let palette: CommandPaletteModel

}
