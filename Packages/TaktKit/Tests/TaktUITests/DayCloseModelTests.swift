import Foundation
import SwiftUI
import TaktCore
import Testing

@testable import TaktADO
@testable import TaktUI

// MARK: - DayCloseModelTests

@MainActor
struct DayCloseModelTests {

  // MARK: Lifecycle

  init() {
    let bookings = bookings
    model = DayCloseModel(
      lines: { day in try bookings.lines(for: day) },
      book: { lines in bookings.book(lines) },
    )
  }

  // MARK: Internal

  /// Return in an inspector field next to the day close must not send bookings to Azure DevOps.
  @Test
  func bookAllNeedsCommandReturn() {
    let shortcut = DayCloseScreen.bookAllShortcut
    #expect(shortcut.key == .return)
    #expect(shortcut.modifiers == .command)
  }

  @Test
  func loadingShowsTheLinesOfTheDay() async {
    bookings.linesByDay[monday.lowerBound] = [line(1, target: 3600)]

    await model.load(monday)

    #expect(model.lines.map(\.title) == ["#1"])
    #expect(!model.loadFailed)
  }

  @Test
  func failedLoadKeepsTheLinesAndReportsIt() async {
    bookings.linesByDay[monday.lowerBound] = [line(1, target: 3600)]
    await model.load(monday)

    bookings.fails = true
    await model.reload()

    #expect(model.loadFailed)
    #expect(model.lines.count == 1)
  }

  @Test
  func linesAreGroupedByWorkItemInNumberOrder() async {
    let second = item(20)
    let first = item(10)
    bookings.linesByDay[monday.lowerBound] = [
      line(1, workItem: second),
      line(2, workItem: first),
      line(3, workItem: second),
    ]

    await model.load(monday)

    #expect(model.groups.map(\.workItem.workItemID) == [10, 20])
    #expect(model.groups.map { $0.lines.map(\.title) } == [["#2"], ["#1", "#3"]])
  }

  @Test
  func openLinesLeaveOutBookedAndInFlightTimeAndSumTheDifferences() async {
    bookings.linesByDay[monday.lowerBound] = [
      line(1, target: 3600),
      line(2, target: 1800, booked: 1800), // booked
      line(3, target: 900, inFlight: 900), // on its way
      line(4, target: 0, booked: 600), // deleted after booking: −600
    ]

    await model.load(monday)

    #expect(model.open.map(\.title) == ["#1", "#4"])
    #expect(model.openSeconds == 3000)
  }

  @Test
  func bookAllBooksOnlyOpenLinesAndReloads() async {
    let open = line(1, target: 3600)
    bookings.linesByDay[monday.lowerBound] = [open, line(2, target: 1800, booked: 1800)]
    await model.load(monday)

    await model.bookAll()

    #expect(bookings.booked == [[open]])
    #expect(model.outcomes == [open.id: .booked])
    #expect(model.open.isEmpty) // the fake books everything it gets
    #expect(!model.isBooking)
  }

  @Test
  func bookAllBooksTheCurrentAmountsNotTheShownOnes() async {
    bookings.linesByDay[monday.lowerBound] = [line(1, target: 7200)]
    await model.load(monday)
    // The entry was shortened in the inspector after the lines were loaded.
    let shortened = line(1, target: 3600)
    bookings.linesByDay[monday.lowerBound] = [shortened]

    await model.bookAll()

    #expect(bookings.booked == [[shortened]])
  }

  @Test
  func anotherDayClearsTheOutcomes() async {
    bookings.linesByDay[monday.lowerBound] = [line(1, target: 3600)]
    await model.load(monday)
    await model.bookAll()
    #expect(!model.outcomes.isEmpty)

    await model.load(monday)
    #expect(!model.outcomes.isEmpty) // reloading the same day keeps them

    await model.load(tuesday)
    #expect(model.outcomes.isEmpty)
    #expect(model.lines.isEmpty)
  }

  // MARK: Private

  /// Booking lines per day; books by moving the target to `booked`.
  @MainActor
  private final class FakeBookings {

    // MARK: Internal

    var linesByDay = [Timestamp: [BookingLine]]()
    var fails = false
    private(set) var booked = [[BookingLine]]()

    func lines(for day: Range<Timestamp>) throws -> [BookingLine] {
      if fails { throw BookingFailure.server }
      return linesByDay[day.lowerBound] ?? []
    }

    func book(_ booking: [BookingLine]) -> [BookingLine.Key: BookingService.Outcome] {
      booked.append(booking)
      for line in booking {
        for (day, dayLines) in linesByDay {
          linesByDay[day] = dayLines.map { $0.id == line.id ? markedBooked($0) : $0 }
        }
      }
      return Dictionary(uniqueKeysWithValues: booking.map { ($0.id, .booked) })
    }

    // MARK: Private

    private func markedBooked(_ line: BookingLine) -> BookingLine {
      var line = line
      line.booked = line.target
      return line
    }
  }

  private let bookings = FakeBookings()
  private let model: DayCloseModel
  private let monday = Timestamp(milliseconds: 1_791_237_600_000)..<Timestamp(milliseconds: 1_791_324_000_000)
  private let tuesday = Timestamp(milliseconds: 1_791_324_000_000)..<Timestamp(milliseconds: 1_791_410_400_000)
  private let defaultItem = WorkItemLink(organization: "contoso", project: "Portal", workItemID: 1, cachedType: "Task")

  private func item(_ id: Int) -> WorkItemLink {
    WorkItemLink(organization: "contoso", project: "Portal", workItemID: id, cachedType: "Task")
  }

  private func line(
    _ number: Int,
    workItem: WorkItemLink? = nil,
    target: Int = 3600,
    booked: Int = 0,
    inFlight: Int = 0,
  ) -> BookingLine {
    BookingLine(
      entryID: EntryID(),
      title: "#\(number)",
      note: nil,
      workItem: workItem ?? defaultItem,
      localDay: "2026-10-05",
      target: target,
      booked: booked,
      inFlight: inFlight,
      failure: nil,
    )
  }
}
