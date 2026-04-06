import Foundation

public struct JNTSchema {
    public static let currentVersion: Int32 = 1

    public static func migrate(db: SQLiteDatabase) throws {
        let rows = try db.query("PRAGMA user_version;")
        let version: Int32
        if let row = rows.first, let v = row["user_version"]?.intValue {
            version = Int32(v)
        } else {
            version = 0
        }

        if version < 1 {
            try createV1(db: db)
        }

        try db.execute("PRAGMA user_version = \(currentVersion);")
    }

    private static func createV1(db: SQLiteDatabase) throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS document (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                content TEXT NOT NULL,
                cursor_position INTEGER DEFAULT 0,
                scroll_position REAL DEFAULT 0.0,
                created_at TEXT NOT NULL,
                modified_at TEXT NOT NULL,
                original_line_ending TEXT DEFAULT 'LF'
            );
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS snapshots (
                seq INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TEXT NOT NULL,
                snapshot_type TEXT NOT NULL,
                edit_summary TEXT,
                diff_data BLOB NOT NULL,
                content_length_before INTEGER,
                content_length_after INTEGER
            );
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
        """)

        try db.execute("""
            CREATE TABLE IF NOT EXISTS children (
                child_uuid TEXT PRIMARY KEY,
                child_path TEXT,
                fork_timestamp TEXT NOT NULL,
                fork_snapshot_seq INTEGER
            );
        """)

        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS limit_snapshots AFTER INSERT ON snapshots
            BEGIN
                DELETE FROM snapshots
                WHERE seq IN (
                    SELECT seq FROM snapshots ORDER BY seq ASC
                    LIMIT max(0, (SELECT count(*) FROM snapshots) - 100)
                );
            END;
        """)
    }
}
