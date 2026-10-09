import Foundation
import TaktCore
import TaktStore

/// Loads everything for a report with few indexed queries.
public struct AnalyticsSource: Sendable {

  // MARK: Lifecycle

  public init(database: AppDatabase) {
    queries = EntryQueries(database: database)
    catalog = CatalogStore(database: database)
    absenceStore = AbsenceStore(database: database)
  }

  // MARK: Public

  public func load(_ range: Range<Timestamp>, now: Timestamp) async throws -> AnalyticsData {
    let entries = try await queries.timeline(in: range, now: now).entries
    return AnalyticsData(
      entries: entries,
      tags: try await catalog.tags(of: entries.map(\.id)),
      catalog: try await catalog.load(),
      workItems: try await queries.workItemLinks(),
    )
  }

  /// Absences of the local days that `range` touches, by `YYYY-MM-DD` (AZ-05).
  public func absences(_ range: Range<Timestamp>, calendar: Calendar) async throws -> [String: AbsenceKind] {
    let last = Timestamp(milliseconds: max(range.lowerBound.milliseconds, range.upperBound.milliseconds - 1))
    return try await absenceStore.absences(
      from: range.lowerBound.localDayString(in: calendar),
      through: last.localDayString(in: calendar),
    )
  }

  /// The first tracked time; the flex account starts there unless a start day is set.
  public func firstTrackedTime() async throws -> Timestamp? {
    try await queries.firstSegmentStart()
  }

  // MARK: Private

  private let queries: EntryQueries
  private let catalog: CatalogStore
  private let absenceStore: AbsenceStore

}
