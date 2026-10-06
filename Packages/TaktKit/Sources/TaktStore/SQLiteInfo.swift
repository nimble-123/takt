import GRDB

/// Information about the SQLite library GRDB links against.
public enum SQLiteInfo {
    /// The SQLite version string, e.g. `3.46.1`.
    public static func version() throws -> String {
        let dbQueue = try DatabaseQueue()
        return try dbQueue.read { db in
            try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? ""
        }
    }
}
