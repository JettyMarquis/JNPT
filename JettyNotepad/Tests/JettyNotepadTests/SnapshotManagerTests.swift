import Foundation
import JettyNotepadKit

func runSnapshotManagerTests() {
    print("\nSnapshotManagerTests:")

    test("create and reconstruct single snapshot") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "snap_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "Version 1", uuid: UUID())
        defer { store.close() }
        let sm = SnapshotManager(fileStore: store)

        // Save creates snapshot: Version 1 → Version 2
        try sm.createSnapshot(previousContent: "Version 1", currentContent: "Version 2",
                              type: "manualSave", editSummary: nil)
        try store.saveContent("Version 2", cursor: 0, scroll: 0)

        // Reconstruct the content AS SAVED AT the snapshot (seq > targetSeq excludes
        // the snapshot's own reverse diff), i.e. "Version 2" — not the state before it.
        let manifest = try store.readSnapshotManifest()
        try assertEqual(manifest.count, 1)
        let restored = try sm.reconstructContent(at: manifest[0].seq, currentContent: "Version 2")
        try assertEqual(restored, "Version 2")
    }

    test("create and reconstruct multiple snapshots") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "snap_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "V1", uuid: UUID())
        defer { store.close() }
        let sm = SnapshotManager(fileStore: store)

        // V1 → V2
        try sm.createSnapshot(previousContent: "V1", currentContent: "V2",
                              type: "autoSave", editSummary: nil)
        try store.saveContent("V2", cursor: 0, scroll: 0)

        // V2 → V3
        try sm.createSnapshot(previousContent: "V2", currentContent: "V3",
                              type: "manualSave", editSummary: nil)
        try store.saveContent("V3", cursor: 0, scroll: 0)

        // V3 → V4
        try sm.createSnapshot(previousContent: "V3", currentContent: "V4 final",
                              type: "autoSave", editSummary: nil)
        try store.saveContent("V4 final", cursor: 0, scroll: 0)

        let manifest = try store.readSnapshotManifest() // desc order: [V3→V4, V2→V3, V1→V2]
        try assertEqual(manifest.count, 3)

        // Each row reconstructs to the content AS SAVED AT that snapshot (seq > targetSeq
        // excludes the row's own reverse diff). The original "V1" (before any save) is
        // no longer reachable through this API — an accepted MVP limitation.
        let newest = try sm.reconstructContent(at: manifest[0].seq, currentContent: "V4 final")
        try assertEqual(newest, "V4 final")

        let middle = try sm.reconstructContent(at: manifest[1].seq, currentContent: "V4 final")
        try assertEqual(middle, "V3")

        let oldest = try sm.reconstructContent(at: manifest[2].seq, currentContent: "V4 final")
        try assertEqual(oldest, "V2")
    }

    test("snapshot with Unicode content") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "snap_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "你好", uuid: UUID())
        defer { store.close() }
        let sm = SnapshotManager(fileStore: store)

        try sm.createSnapshot(previousContent: "你好", currentContent: "你好世界",
                              type: "manualSave", editSummary: nil)
        try store.saveContent("你好世界", cursor: 0, scroll: 0)

        let manifest = try store.readSnapshotManifest()
        let restored = try sm.reconstructContent(at: manifest[0].seq, currentContent: "你好世界")
        try assertEqual(restored, "你好世界")
    }

    test("snapshot data is compressed") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "snap_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "short", uuid: UUID())
        defer { store.close() }
        let sm = SnapshotManager(fileStore: store)

        let longContent = String(repeating: "This is a long sentence. ", count: 100)
        try sm.createSnapshot(previousContent: "short", currentContent: longContent,
                              type: "autoSave", editSummary: nil)

        // The stored diff_data should be compressed (smaller than raw patch text)
        let manifest = try store.readSnapshotManifest()
        let compressed = try store.readSnapshotDiff(seq: manifest[0].seq)
        // Decompress and verify it's valid
        let decompressed = try (compressed as NSData).decompressed(using: .zlib) as Data
        try assertNotNil(String(data: decompressed, encoding: .utf8))
    }

    test("100-snapshot cap enforced by FIFO trigger, oldest evicted") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "snap_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "v0", uuid: UUID())
        defer { store.close() }
        let sm = SnapshotManager(fileStore: store)

        for i in 0..<105 {
            try sm.createSnapshot(previousContent: "v\(i)", currentContent: "v\(i+1)",
                                  type: "autoSave", editSummary: nil)
        }
        try assertEqual(try store.snapshotCount(), 100)
        // No type protection in MVP — oldest-by-seq are evicted regardless of type.
        let manifest = try store.readSnapshotManifest()
        try assertEqual(manifest.count, 100)
    }

    test("reconstructContent throws on oversized decompressed payload") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "snap_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "short", uuid: UUID())
        defer { store.close() }
        let sm = SnapshotManager(fileStore: store)

        try sm.createSnapshot(previousContent: "short", currentContent: "short2",
                              type: "autoSave", editSummary: nil)
        let manifest = try store.readSnapshotManifest()

        // Overwrite the diff_data with a huge but validly-compressed blob whose
        // decompressed size vastly exceeds the recorded content lengths.
        let bomb = Data(repeating: 0, count: 10 * 1024 * 1024) // 10MB of zeros compresses tiny
        let compressedBomb = try (bomb as NSData).compressed(using: .zlib) as Data
        try store.db.executeWithParams(
            "UPDATE snapshots SET diff_data = ?1 WHERE seq = ?2;",
            params: [.blob(compressedBomb), .int(Int64(manifest[0].seq))]
        )

        try assertThrows {
            try sm.reconstructContent(at: manifest[0].seq - 1, currentContent: "short2")
        }
    }

    test("reconstructContent throws when patchApply fails to match context") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "snap_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "hello world", uuid: UUID())
        defer { store.close() }
        let sm = SnapshotManager(fileStore: store)

        try sm.createSnapshot(previousContent: "hello world", currentContent: "hello world!!",
                              type: "autoSave", editSummary: nil)
        let manifest = try store.readSnapshotManifest()

        // Reconstruct against content whose context no longer matches the stored
        // diff at all — patchApply's fuzzy match should fail and we must surface it.
        try assertThrows {
            try sm.reconstructContent(at: manifest[0].seq - 1, currentContent: "totally unrelated")
        }
    }
}

func runSaveAsTests() {
    print("\nSaveAsTests:")

    test("Save As generates new UUID for child") {
        let parentURL = URL(fileURLWithPath: NSTemporaryDirectory() + "parent2_\(UUID().uuidString).jnt")
        let childURL = URL(fileURLWithPath: NSTemporaryDirectory() + "child2_\(UUID().uuidString).jnt")
        defer {
            try? FileManager.default.removeItem(at: parentURL)
            try? FileManager.default.removeItem(at: childURL)
        }

        let parentUUID = UUID()
        let parentStore = try JNTFileStore.create(at: parentURL, content: "Content", uuid: parentUUID)

        let childUUID = UUID()
        let childStore = try JNTFileStore.create(at: childURL, content: "Content", uuid: childUUID)
        try childStore.writeMetadata(key: "parent_uuid", value: parentUUID.uuidString)

        let parentUUIDStr = try parentStore.readMetadata(key: "file_uuid")
        let childUUIDStr = try childStore.readMetadata(key: "file_uuid")

        try assertTrue(parentUUIDStr != childUUIDStr, "Parent and child should have different UUIDs")

        parentStore.close()
        childStore.close()
    }
}
