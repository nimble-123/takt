import TaktCore
import TaktStore

/// Loads everything for a report with few indexed queries.
public struct AnalyticsSource: Sendable {
    private let queries: EntryQueries
    private let catalog: CatalogStore

    public init(database: AppDatabase) {
        queries = EntryQueries(database: database)
        catalog = CatalogStore(database: database)
    }

    public func load(_ range: Range<Timestamp>, now: Timestamp) async throws -> AnalyticsData {
        let entries = try await queries.timeline(in: range, now: now).entries
        return AnalyticsData(
            entries: entries,
            tags: try await catalog.tags(of: entries.map(\.id)),
            catalog: try await catalog.load(),
            workItems: try await queries.workItemLinks()
        )
    }
}
