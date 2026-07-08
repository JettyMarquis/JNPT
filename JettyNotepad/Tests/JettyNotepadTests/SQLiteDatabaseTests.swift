import Foundation
import JettyNotepadKit

func runSQLiteDatabaseTests() {
    print("SQLiteDatabaseTests:")

    test("WAL mode is set on open") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }
        let rows = try db.query("PRAGMA journal_mode;")
        try assertEqual(rows.first?["journal_mode"]?.textValue, "wal")
    }

    test("foreign keys enabled") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }
        let rows = try db.query("PRAGMA foreign_keys;")
        try assertEqual(rows.first?["foreign_keys"]?.intValue, 1)
    }

    test("create table, insert, query") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT, score REAL);")
        try db.executeWithParams("INSERT INTO test VALUES (?1, ?2, ?3);",
                                 params: [.int(1), .text("Alice"), .double(95.5)])
        try db.executeWithParams("INSERT INTO test VALUES (?1, ?2, ?3);",
                                 params: [.int(2), .text("Bob"), .double(87.0)])

        let rows = try db.query("SELECT * FROM test ORDER BY id;")
        try assertEqual(rows.count, 2)
        try assertEqual(rows[0]["name"]?.textValue, "Alice")
        try assertEqual(rows[0]["score"]?.doubleValue, 95.5)
        try assertEqual(rows[1]["name"]?.textValue, "Bob")
    }

    test("insertReturningRowId") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try db.execute("CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, val TEXT);")
        let id1 = try db.insertReturningRowId("INSERT INTO items (val) VALUES (?1);", params: [.text("first")])
        let id2 = try db.insertReturningRowId("INSERT INTO items (val) VALUES (?1);", params: [.text("second")])
        try assertEqual(id1, 1)
        try assertEqual(id2, 2)
    }

    test("blob round-trip") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try db.execute("CREATE TABLE blobs (id INTEGER PRIMARY KEY, data BLOB);")
        let original = Data([0x00, 0x01, 0xFF, 0xFE, 0x42])
        try db.executeWithParams("INSERT INTO blobs VALUES (1, ?1);", params: [.blob(original)])
        let rows = try db.query("SELECT data FROM blobs WHERE id = 1;")
        try assertEqual(rows.first?["data"]?.blobValue, original)
    }

    test("null handling") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try db.execute("CREATE TABLE nullable (id INTEGER PRIMARY KEY, val TEXT);")
        try db.executeWithParams("INSERT INTO nullable VALUES (1, ?1);", params: [.null])
        let rows = try db.query("SELECT val FROM nullable WHERE id = 1;")
        try assertEqual(rows.first?["val"], .null)
    }

    test("transaction commit") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try db.execute("CREATE TABLE txn (id INTEGER PRIMARY KEY);")
        try db.inTransaction {
            try db.executeWithParams("INSERT INTO txn VALUES (?1);", params: [.int(1)])
            try db.executeWithParams("INSERT INTO txn VALUES (?1);", params: [.int(2)])
        }
        let rows = try db.query("SELECT count(*) as cnt FROM txn;")
        try assertEqual(rows.first?["cnt"]?.intValue, 2)
    }

    test("transaction rollback on error") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }

        try db.execute("CREATE TABLE txn2 (id INTEGER PRIMARY KEY);")
        try db.executeWithParams("INSERT INTO txn2 VALUES (?1);", params: [.int(1)])

        do {
            try db.inTransaction {
                try db.executeWithParams("INSERT INTO txn2 VALUES (?1);", params: [.int(2)])
                try db.executeWithParams("INSERT INTO txn2 VALUES (?1);", params: [.int(2)]) // dup
            }
        } catch {}

        let rows = try db.query("SELECT count(*) as cnt FROM txn2;")
        try assertEqual(rows.first?["cnt"]?.intValue, 1)
    }

    test("invalid SQL throws") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        defer { db.close() }
        try assertThrows { try db.execute("NOT VALID SQL;") }
    }

    test("query after close throws") {
        let path = NSTemporaryDirectory() + "test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        db.close()
        try assertThrows { try db.query("SELECT 1;") }
    }

    test("integrity_check rejects a corrupted (non-SQLite) file") {
        let path = NSTemporaryDirectory() + "corrupt_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        try Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xAB, 0xCD]).write(to: URL(fileURLWithPath: path))
        try assertThrows { try SQLiteDatabase(path: path) }
    }

    test("integrity_check failure does not mutate the file on disk") {
        // integrity_check must run before PRAGMA journal_mode=WAL, so a rejected
        // untrusted file is never written to before being judged unsafe.
        let path = NSTemporaryDirectory() + "corrupt2_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0xFF, 0xFE, 0xAB, 0xCD])
        try garbage.write(to: URL(fileURLWithPath: path))
        try assertThrows { try SQLiteDatabase(path: path) }
        let after = try Data(contentsOf: URL(fileURLWithPath: path))
        try assertEqual(after, garbage)
    }

    test("integrity_check passes on a freshly created database") {
        let path = NSTemporaryDirectory() + "fresh_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let db = try SQLiteDatabase(path: path)
        db.close()
    }
}
