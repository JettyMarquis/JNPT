import Foundation
import JettyNotepadKit

func runJNTSchemaTests() {
    print("\nJNTSchemaTests:")

    test("migrate creates all tables") {
        let path = NSTemporaryDirectory() + "schema_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try JNTSchema.migrate(db: db)

        let tables = try db.query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
        let names = tables.compactMap { $0["name"]?.textValue }
        try assertTrue(names.contains("document"), "missing document table")
        try assertTrue(names.contains("snapshots"), "missing snapshots table")
        try assertTrue(names.contains("metadata"), "missing metadata table")
    }

    test("migrate sets user_version") {
        let path = NSTemporaryDirectory() + "schema_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try JNTSchema.migrate(db: db)
        let rows = try db.query("PRAGMA user_version;")
        try assertEqual(rows.first?["user_version"]?.intValue, Int64(JNTSchema.currentVersion))
    }

    test("migrate is idempotent") {
        let path = NSTemporaryDirectory() + "schema_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try JNTSchema.migrate(db: db)
        try JNTSchema.migrate(db: db)  // Should not fail

        let rows = try db.query("PRAGMA user_version;")
        try assertEqual(rows.first?["user_version"]?.intValue, Int64(JNTSchema.currentVersion))
    }

    test("snapshot limit trigger exists") {
        let path = NSTemporaryDirectory() + "schema_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try JNTSchema.migrate(db: db)
        let triggers = try db.query("SELECT name FROM sqlite_master WHERE type='trigger';")
        let names = triggers.compactMap { $0["name"]?.textValue }
        try assertTrue(names.contains("limit_snapshots"), "missing limit_snapshots trigger")
    }

    test("document table CHECK constraint") {
        let path = NSTemporaryDirectory() + "schema_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try JNTSchema.migrate(db: db)

        // id=1 should work
        try db.executeWithParams(
            "INSERT INTO document (id, content, created_at, modified_at) VALUES (1, ?1, ?2, ?3);",
            params: [.text(""), .text("2024-01-01T00:00:00Z"), .text("2024-01-01T00:00:00Z")]
        )

        // id=2 should fail
        try assertThrows {
            try db.executeWithParams(
                "INSERT INTO document (id, content, created_at, modified_at) VALUES (2, ?1, ?2, ?3);",
                params: [.text(""), .text("2024-01-01T00:00:00Z"), .text("2024-01-01T00:00:00Z")]
            )
        }
    }

    test("snapshot trigger enforces 100 limit") {
        let path = NSTemporaryDirectory() + "schema_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try JNTSchema.migrate(db: db)

        for i in 1...105 {
            try db.executeWithParams(
                "INSERT INTO snapshots (timestamp, snapshot_type, diff_data) VALUES (?1, 'autoSave', ?2);",
                params: [.text("2024-01-01T00:00:\(String(format: "%02d", i % 60))Z"), .blob(Data([0x00]))]
            )
        }

        let rows = try db.query("SELECT count(*) as cnt FROM snapshots;")
        try assertEqual(rows.first?["cnt"]?.intValue, 100)
    }
}
