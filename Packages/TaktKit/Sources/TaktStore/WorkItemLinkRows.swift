import GRDB
import TaktCore

extension WorkItemLink: TableRow {
    static let table = "work_item_link"
    var rowID: String { id.uuidString }

    init(row: Row) throws {
        self.init(
            id: try row.id("id"),
            organization: row["org"],
            project: row["project"],
            workItemID: row["work_item_id"],
            cachedTitle: row["cached_title"],
            cachedType: row["cached_type"],
            cachedState: row["cached_state"],
            cachedAt: row.optionalTimestamp("cached_at")
        )
    }

    var columns: [String: (any DatabaseValueConvertible)?] {
        [
            "id": id.uuidString, "org": organization, "project": project, "work_item_id": workItemID,
            "cached_title": cachedTitle, "cached_type": cachedType, "cached_state": cachedState,
            "cached_at": cachedAt?.milliseconds,
        ]
    }
}

extension EntryQueries {
    /// All linked work items by ID; the table holds one row per work item.
    public func workItemLinks() async throws -> [WorkItemLinkID: WorkItemLink] {
        try await database.writer.read { db in
            let links = try Row.fetchAll(db, sql: "SELECT * FROM work_item_link").map(WorkItemLink.init(row:))
            return Dictionary(uniqueKeysWithValues: links.map { ($0.id, $0) })
        }
    }
}
