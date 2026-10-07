import Foundation
import GRDB
import TaktCore

extension Schema {
    /// Full-text index over entries, catalog and cached work items (HW-06). Triggers keep it current,
    /// so no code path has to remember it.
    static func v3(_ db: Database) throws {
        try db.execute(
            sql: """
                CREATE VIRTUAL TABLE search_index USING fts5(
                  kind UNINDEXED, ref UNINDEXED, title, body,
                  tokenize = 'unicode61 remove_diacritics 2'
                );
                """
        )
        // `$.` stands for the row: `NEW.` in triggers, nothing when filling the index from the table.
        let sources: [(table: String, kind: String, title: String, body: String, condition: String)] = [
            ("time_entry", "entry", "$.title", "COALESCE($.note, '')", "$.deleted_at IS NULL"),
            ("project", "project", "$.name", "COALESCE($.area_path, '')", "1"),
            ("task", "task", "$.name", "''", "1"),
            ("category", "category", "$.name", "''", "1"),
            ("tag", "tag", "$.name", "''", "1"),
            (
                "work_item_link", "workItem", "COALESCE($.cached_title, '')",
                "'#' || $.work_item_id || ' ' || COALESCE($.description_excerpt, '')", "1"
            ),
        ]
        for source in sources {
            func row(_ expression: String, _ prefix: String) -> String {
                expression.replacingOccurrences(of: "$.", with: prefix)
            }
            let insertNew = """
                INSERT INTO search_index (kind, ref, title, body)
                SELECT '\(source.kind)', NEW.id, \(row(source.title, "NEW.")), \(row(source.body, "NEW."))
                WHERE \(row(source.condition, "NEW."));
                """
            let remove = "DELETE FROM search_index WHERE kind = '\(source.kind)' AND ref = OLD.id;"
            try db.execute(
                sql: """
                    CREATE TRIGGER search_\(source.table)_insert AFTER INSERT ON \(source.table) BEGIN
                      \(insertNew)
                    END;
                    CREATE TRIGGER search_\(source.table)_update AFTER UPDATE ON \(source.table) BEGIN
                      \(remove)
                      \(insertNew)
                    END;
                    CREATE TRIGGER search_\(source.table)_delete AFTER DELETE ON \(source.table) BEGIN
                      \(remove)
                    END;
                    INSERT INTO search_index (kind, ref, title, body)
                    SELECT '\(source.kind)', id, \(row(source.title, "")), \(row(source.body, ""))
                    FROM \(source.table) WHERE \(row(source.condition, ""));
                    """
            )
        }
    }
}

/// One hit of the full-text search.
public struct SearchHit: Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case entry, project, task, category, tag, workItem
    }

    public var kind: Kind
    /// ID of the row in its table.
    public var ref: String
    public var title: String
    /// Matching part of the note or description with `**` around the hits.
    public var snippet: String?

    public var id: String { "\(kind.rawValue)|\(ref)" }
}

/// Full-text search over the index (HW-06).
public struct SearchIndex: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// Hits for all words of `text` (each as a prefix), best first.
    public func search(_ text: String, limit: Int = 50) async throws -> [SearchHit] {
        guard let query = Self.matchQuery(text) else { return [] }
        return try await database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT kind, ref, title, snippet(search_index, 3, '**', '**', '…', 10) AS snippet
                    FROM search_index
                    WHERE search_index MATCH ?
                    ORDER BY bm25(search_index, 0, 0, 10, 1)
                    LIMIT ?
                    """,
                arguments: [query, limit]
            ).compactMap { row in
                guard let kind = SearchHit.Kind(rawValue: row["kind"]) else { return nil }
                let snippet: String? = row["snippet"]
                return SearchHit(
                    kind: kind, ref: row["ref"], title: row["title"],
                    snippet: snippet?.contains("**") == true ? snippet : nil
                )
            }
        }
    }

    /// `"word1"* "word2"*` – every word as a quoted prefix, so user input never becomes FTS syntax.
    static func matchQuery(_ text: String) -> String? {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isPunctuation && $0 != "#" })
            .map { $0.replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "#", with: "") }
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return nil }
        return words.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}
