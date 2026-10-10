import Foundation
import Observation
import TaktADO
import TaktCore
import TaktStore

// MARK: - DayCloseModel

/// State of the day close: the day's booking lines, the outcome of the last booking and the
/// figures derived from them (UC-07, DO-20–DO-27). `DayCloseScreen` only renders it.
@Observable
final class DayCloseModel {

  // MARK: Lifecycle

  /// `lines` and `book` stand in for the `BookingCoordinator` in tests.
  init(
    lines: @escaping @MainActor (Range<Timestamp>) async throws -> [BookingLine],
    book: @escaping @MainActor ([BookingLine]) async -> [BookingLine.Key: BookingService.Outcome],
  ) {
    loadLines = lines
    bookLines = book
  }

  convenience init(booking: BookingCoordinator) {
    self.init(
      lines: { day in try await booking.lines(for: day) },
      book: { lines in await booking.book(lines) },
    )
  }

  // MARK: Internal

  /// The lines of one work item.
  struct Group: Identifiable {
    var workItem: WorkItemLink
    var lines: [BookingLine]

    var id: WorkItemLinkID {
      workItem.id
    }
  }

  private(set) var lines = [BookingLine]()
  /// Results of the last "Book All", per line; cleared when the day changes.
  private(set) var outcomes = [BookingLine.Key: BookingService.Outcome]()
  private(set) var isBooking = false
  private(set) var loadFailed = false

  /// Lines with a difference that is not on its way already.
  var open: [BookingLine] {
    lines.filter(\.isOpen)
  }

  /// The signed sum of the open differences, in seconds.
  var openSeconds: Int {
    open.reduce(0) { $0 + $1.difference }
  }

  /// Open lines the user did not uncheck; "Book" sends these.
  var selected: [BookingLine] {
    open.filter { !excluded.contains($0.id) }
  }

  /// The signed sum of the selected differences, in seconds.
  var selectedSeconds: Int {
    selected.reduce(0) { $0 + $1.difference }
  }

  /// Lines per work item, ordered by work item number.
  var groups: [Group] {
    Dictionary(grouping: lines, by: \.workItem.id).values
      .compactMap { lines in lines.first.map { Group(workItem: $0.workItem, lines: lines) } }
      .sorted { $0.workItem.workItemID < $1.workItem.workItemID }
  }

  func isSelected(_ line: BookingLine) -> Bool {
    line.isOpen && !excluded.contains(line.id)
  }

  /// Checks or unchecks an open line for booking.
  func setSelected(_ selected: Bool, _ line: BookingLine) {
    if selected { excluded.remove(line.id) } else { excluded.insert(line.id) }
  }

  /// Loads the lines of `day`. Results of booking another day do not belong to this one, so a
  /// new day clears them.
  func load(_ day: Range<Timestamp>) async {
    if day != shownDay {
      outcomes = [:]
      excluded = []
      shownDay = day
    }
    do {
      let loaded = try await loadLines(day)
      // The day changed while loading: that day's own load sets the lines.
      guard !Task.isCancelled, day == shownDay else { return }
      lines = loaded
      loadFailed = false
    } catch {
      guard !Task.isCancelled, day == shownDay else { return }
      loadFailed = true
    }
  }

  /// Reloads the shown day, e.g. after the queue was sent again.
  func reload() async {
    guard let shownDay else { return }
    await load(shownDay)
  }

  /// Books the selected open lines of the shown day, then reloads it. Reloads first: the shown
  /// lines may predate an edit, and a stale target would book the wrong amount.
  func bookAll() async {
    isBooking = true
    await reload()
    outcomes = await bookLines(selected)
    await reload()
    isBooking = false
  }

  // MARK: Private

  private let loadLines: @MainActor (Range<Timestamp>) async throws -> [BookingLine]
  private let bookLines: @MainActor ([BookingLine]) async -> [BookingLine.Key: BookingService.Outcome]
  private var shownDay: Range<Timestamp>?
  /// Lines unchecked in the review; kept by key, so they stay unchecked across reloads of the day.
  private var excluded = Set<BookingLine.Key>()

}

extension BookingLine {
  /// A difference to book that is not on its way already; the day close and ⌘K book these.
  var isOpen: Bool {
    difference != 0 && inFlight == 0
  }
}
