import Foundation
import GRDB
import TaktCore

extension WorkItemLink: TableRow {
    static let table = "work_item_link"
    var rowID: String { id.uuidString }

    init(row: Row) throws {
        // Only cached details: a damaged value must not break the search.
        let tags = (try? JSONDecoder().decode([String].self, from: Data(((row["tags"] as String?) ?? "[]").utf8))) ?? []
        self.init(
            id: try row.id("id"),
            organization: row["org"],
            project: row["project"],
            workItemID: row["work_item_id"],
            cachedTitle: row["cached_title"],
            cachedType: row["cached_type"],
            cachedState: row["cached_state"],
            cachedAt: row.optionalTimestamp("cached_at"),
            assignedTo: row["assigned_to"],
            iterationPath: row["iteration_path"],
            remainingWork: row["remaining_work"],
            completedWork: row["completed_work"],
            parentID: row["parent_id"],
            descriptionExcerpt: row["description_excerpt"],
            tags: tags
        )
    }

    var columns: [String: (any DatabaseValueConvertible)?] {
        let tags = (try? JSONEncoder().encode(tags)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
        return [
            "id": id.uuidString, "org": organization, "project": project, "work_item_id": workItemID,
            "cached_title": cachedTitle, "cached_type": cachedType, "cached_state": cachedState,
            "cached_at": cachedAt?.milliseconds, "assigned_to": assignedTo, "iteration_path": iterationPath,
            "remaining_work": remainingWork, "completed_work": completedWork, "parent_id": parentID,
            "description_excerpt": descriptionExcerpt, "tags": tags,
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

/// Work items seen in searches and suggestions, for instant local hits (DO-11).
public struct WorkItemCache: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Stores fresh details; an item seen before keeps its local ID, so links stay valid.
    @discardableResult
    public func store(_ items: [WorkItemLink]) async throws -> [WorkItemLink] {
        try await database.writer.write { db in
            try items.map { item in
                let existing = try Row.fetchOne(
                    db, sql: "SELECT * FROM work_item_link WHERE org = ? AND work_item_id = ?",
                    arguments: [item.organization, item.workItemID]
                ).map(WorkItemLink.init(row:))
                let stored = existing?.updated(with: item) ?? item
                let columns = stored.columns.sorted { $0.key < $1.key }
                let updates = columns.filter { $0.key != "id" }.map { "\($0.key) = excluded.\($0.key)" }
                try db.execute(
                    sql: """
                        INSERT INTO work_item_link (\(columns.map(\.key).joined(separator: ", ")))
                        VALUES (\(databaseQuestionMarks(count: columns.count)))
                        ON CONFLICT(id) DO UPDATE SET \(updates.joined(separator: ", "))
                        """,
                    arguments: StatementArguments(columns.map(\.value))
                )
                return stored
            }
        }
    }

    /// Cached items whose ID equals `id` or whose title contains `text`, most recently seen first.
    public func search(_ text: String, id: Int?, limit: Int = 8) async throws -> [WorkItemLink] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM work_item_link
                    WHERE work_item_id = :id OR (:text != '' AND cached_title LIKE :pattern ESCAPE '\\')
                    ORDER BY work_item_id = :id DESC, cached_at DESC
                    LIMIT :limit
                    """,
                arguments: [
                    "id": id ?? -1, "text": text, "limit": limit,
                    "pattern": "%"
                        + text.replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%",
                ]
            ).map(WorkItemLink.init(row:))
        }
    }

    /// Work items of the most recently used entries (DO suggestions: "zuletzt in der App verwendet").
    public func recentlyUsed(limit: Int = 5) async throws -> [WorkItemLink] {
        try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT l.* FROM work_item_link l
                    JOIN time_entry e ON e.work_item_link_id = l.id
                    WHERE e.deleted_at IS NULL
                    GROUP BY l.id
                    ORDER BY MAX(e.updated_at) DESC
                    LIMIT ?
                    """,
                arguments: [limit]
            ).map(WorkItemLink.init(row:))
        }
    }

    public func link(_ id: WorkItemLinkID) async throws -> WorkItemLink? {
        try await database.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM work_item_link WHERE id = ?", arguments: [id.uuidString])
                .map(WorkItemLink.init(row:))
        }
    }
}
