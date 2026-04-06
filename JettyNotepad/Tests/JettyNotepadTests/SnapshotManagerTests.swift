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

        // Reconstruct Version 1 from Version 2
        let manifest = try store.readSnapshotManifest()
        try assertEqual(manifest.count, 1)
        let restored = try sm.reconstructContent(at: manifest[0].seq, currentContent: "Version 2")
        try assertEqual(restored, "Version 1")
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

        let manifest = try store.readSnapshotManifest() // desc order
        try assertEqual(manifest.count, 3)

        // Reconstruct each version
        let v3 = try sm.reconstructContent(at: manifest[0].seq, currentContent: "V4 final")
        try assertEqual(v3, "V3")

        let v2 = try sm.reconstructContent(at: manifest[1].seq, currentContent: "V4 final")
        try assertEqual(v2, "V2")

        let v1 = try sm.reconstructContent(at: manifest[2].seq, currentContent: "V4 final")
        try assertEqual(v1, "V1")
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
        try assertEqual(restored, "你好")
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

    test("eviction does not crash with few snapshots") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "snap_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "test", uuid: UUID())
        defer { store.close() }
        let sm = SnapshotManager(fileStore: store)

        // Add a few snapshots — eviction should be a no-op
        for i in 1...5 {
            try sm.createSnapshot(previousContent: "v\(i)", currentContent: "v\(i+1)",
                                  type: "autoSave", editSummary: nil)
        }
        try sm.evictIfNeeded()
        try assertEqual(try store.snapshotCount(), 5)
    }
}

func runSaveAsTests() {
    print("\nSaveAsTests:")

    test("Save As creates parent-child link") {
        let parentURL = URL(fileURLWithPath: NSTemporaryDirectory() + "parent_\(UUID().uuidString).jnt")
        let childURL = URL(fileURLWithPath: NSTemporaryDirectory() + "child_\(UUID().uuidString).jnt")
        defer {
            try? FileManager.default.removeItem(at: parentURL)
            try? FileManager.default.removeItem(at: childURL)
        }

        // Create parent
        let parentUUID = UUID()
        let parentStore = try JNTFileStore.create(at: parentURL, content: "Parent content", uuid: parentUUID)
        let parentSM = SnapshotManager(fileStore: parentStore)

        // Simulate a save to create history
        try parentSM.createSnapshot(previousContent: "Parent content",
                                    currentContent: "Parent content v2",
                                    type: "manualSave", editSummary: nil)
        try parentStore.saveContent("Parent content v2", cursor: 0, scroll: 0)

        // Simulate Save As — create fork point + child
        try parentSM.createSnapshot(previousContent: "Parent content v2",
                                    currentContent: "Parent content v2",
                                    type: "forkPoint", editSummary: nil)

        let parentSnaps = try parentStore.readSnapshotManifest()
        let forkSeq = parentSnaps.first?.seq ?? 0

        let childUUID = UUID()
        try parentStore.addChild(uuid: childUUID, path: childURL.path,
                                 forkTimestamp: Date(), forkSeq: forkSeq)

        // Create child .jnt
        let childStore = try JNTFileStore.create(at: childURL, content: "Parent content v2", uuid: childUUID)
        try childStore.writeMetadata(key: "parent_uuid", value: parentUUID.uuidString)
        try childStore.writeMetadata(key: "parent_path", value: parentURL.path)
        try childStore.writeMetadata(key: "parent_snapshot_seq", value: "\(forkSeq)")

        // Verify parent has child
        let children = try parentStore.readChildren()
        try assertEqual(children.count, 1)
        try assertEqual(children[0].childUUID, childUUID)

        // Verify child has parent reference
        let pUUID = try childStore.readMetadata(key: "parent_uuid")
        try assertEqual(pUUID, parentUUID.uuidString)

        // Verify child content
        let childContent = try childStore.readContent()
        try assertEqual(childContent, "Parent content v2")

        parentStore.close()
        childStore.close()
    }

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
