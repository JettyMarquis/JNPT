import Foundation
import JettyNotepadKit

func runJNTFileStoreTests() {
    print("\nJNTFileStoreTests:")

    test("create and reopen reads same content") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }

        let store = try JNTFileStore.create(at: url, content: "Hello, World!", uuid: UUID())
        store.close()

        let reopened = try JNTFileStore(url: url)
        defer { reopened.close() }
        let content = try reopened.readContent()
        try assertEqual(content, "Hello, World!")
    }

    test("create sets format_version") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "test", uuid: UUID())
        defer { store.close() }
        try assertEqual(try store.readMetadata(key: "format_version"), "1")
    }

    test("create sets file_uuid") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let myUUID = UUID()
        let store = try JNTFileStore.create(at: url, content: "test", uuid: myUUID)
        defer { store.close() }
        try assertEqual(try store.readMetadata(key: "file_uuid"), myUUID.uuidString)
    }

    test("create sets display_name from first line") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "Hello, World!", uuid: UUID())
        defer { store.close() }
        try assertEqual(try store.readMetadata(key: "display_name"), "Hello, World!")
    }

    test("save and read content round-trip") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "original", uuid: UUID())
        defer { store.close() }

        try store.saveContent("Updated content", cursor: 5, scroll: 10.0)
        let state = try store.readDocumentState()
        try assertEqual(state.content, "Updated content")
        try assertEqual(state.cursorPosition, 5)
        try assertTrue(abs(state.scrollPosition - 10.0) < 0.001, "scroll mismatch")
    }

    test("save updates modified_at") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "original", uuid: UUID())
        defer { store.close() }

        let state1 = try store.readDocumentState()
        Thread.sleep(forTimeInterval: 0.05)
        try store.saveContent("new", cursor: 0, scroll: 0)
        let state2 = try store.readDocumentState()
        try assertGreaterThan(state2.modifiedAt, state1.modifiedAt)
    }

    test("save updates display_name from first line") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "original", uuid: UUID())
        defer { store.close() }

        try store.saveContent("My Document Title\nBody text", cursor: 0, scroll: 0)
        try assertEqual(try store.readMetadata(key: "display_name"), "My Document Title")
    }

    test("empty content gives Untitled display name") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "", uuid: UUID())
        defer { store.close() }
        try assertEqual(try store.readMetadata(key: "display_name"), "Untitled")
    }

    test("metadata write and read") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "test", uuid: UUID())
        defer { store.close() }

        try store.writeMetadata(key: "custom", value: "hello")
        try assertEqual(try store.readMetadata(key: "custom"), "hello")
    }

    test("metadata upsert") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "test", uuid: UUID())
        defer { store.close() }

        try store.writeMetadata(key: "k", value: "v1")
        try store.writeMetadata(key: "k", value: "v2")
        try assertEqual(try store.readMetadata(key: "k"), "v2")
    }

    test("read all metadata") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "test", uuid: UUID())
        defer { store.close() }

        let all = try store.readMetadata()
        try assertTrue(all.keys.contains("format_version"), "missing format_version")
        try assertTrue(all.keys.contains("file_uuid"), "missing file_uuid")
        try assertTrue(all.keys.contains("display_name"), "missing display_name")
    }

    test("snapshot insert and read") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "test", uuid: UUID())
        defer { store.close() }

        let diff = Data("test diff".utf8)
        let seq = try store.insertSnapshot(type: "manualSave", editSummary: "typing",
                                           diffData: diff, lengthBefore: 100, lengthAfter: 110)
        try assertEqual(seq, 1)

        let manifest = try store.readSnapshotManifest()
        try assertEqual(manifest.count, 1)
        try assertEqual(manifest[0].snapshotType, "manualSave")
        try assertEqual(manifest[0].editSummary, "typing")

        let readDiff = try store.readSnapshotDiff(seq: Int(seq))
        try assertEqual(readDiff, diff)
    }

    test("snapshot count") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "test", uuid: UUID())
        defer { store.close() }

        try assertEqual(try store.snapshotCount(), 0)
        _ = try store.insertSnapshot(type: "autoSave", editSummary: nil,
                                     diffData: Data([0x00]), lengthBefore: 0, lengthAfter: 1)
        try assertEqual(try store.snapshotCount(), 1)
    }

    test("add and read child") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "test", uuid: UUID())
        defer { store.close() }

        let childUUID = UUID()
        try store.addChild(uuid: childUUID, path: "/tmp/child.jnt",
                           forkTimestamp: Date(), forkSeq: 1)
        let children = try store.readChildren()
        try assertEqual(children.count, 1)
        try assertEqual(children[0].childUUID, childUUID)
        try assertEqual(children[0].childPath, "/tmp/child.jnt")
    }

    test("jnt file uses WAL mode") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "test_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "test", uuid: UUID())
        store.close()

        let rawDB = try SQLiteDatabase(path: url.path)
        defer { rawDB.close() }
        let rows = try rawDB.query("PRAGMA journal_mode;")
        try assertEqual(rows.first?["journal_mode"]?.textValue, "wal")
    }

    test("displayNameFromContent helper") {
        try assertEqual(JNTFileStore.displayNameFromContent(""), "Untitled")
        try assertEqual(JNTFileStore.displayNameFromContent("   "), "Untitled")
        try assertEqual(JNTFileStore.displayNameFromContent("Title\nBody"), "Title")
        try assertEqual(JNTFileStore.displayNameFromContent("Short"), "Short")

        let long = String(repeating: "A", count: 100)
        let name = JNTFileStore.displayNameFromContent(long)
        try assertTrue(name.count <= 60, "name too long: \(name.count)")
        try assertTrue(name.hasSuffix("..."), "should end with ...")
    }
}
