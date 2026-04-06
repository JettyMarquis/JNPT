import Foundation
import JettyNotepadKit

func runExternalFileManagerTests() {
    print("\nExternalFileManagerTests:")

    test("companion URL generation") {
        let uuid = UUID()
        let url = ExternalFileManager.companionURL(for: uuid)
        let prefix = String(uuid.uuidString.prefix(2).lowercased())
        try assertTrue(url.path.contains("companions/\(prefix)/"), "wrong prefix dir")
        try assertTrue(url.path.hasSuffix(".jnt"), "should end with .jnt")
    }

    test("ensure folder structure") {
        // Clean up first
        let baseDir = ExternalFileManager.jettyNoteFolder
        let testDir = baseDir.appendingPathComponent("_test_\(UUID().uuidString)")
        // Just verify ensureFolderStructure doesn't throw
        try ExternalFileManager.ensureFolderStructure()
        let fm = FileManager.default
        try assertTrue(fm.fileExists(atPath: baseDir.appendingPathComponent("companions").path),
                       "companions dir missing")
        try assertTrue(fm.fileExists(atPath: baseDir.appendingPathComponent("orphans").path),
                       "orphans dir missing")
    }

    test("open or create companion") {
        let tmpDir = NSTemporaryDirectory() + "jnpt_ext_test_\(UUID().uuidString)/"
        try FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        let txtURL = URL(fileURLWithPath: tmpDir + "test.txt")
        try "Hello external".write(to: txtURL, atomically: true, encoding: .utf8)

        let (store, uuid, isNew) = try ExternalFileManager.openOrCreateCompanion(
            for: txtURL, content: "Hello external")
        defer { store.close() }

        try assertTrue(isNew, "should be new")
        try assertNotNil(uuid)
        let content = try store.readContent()
        try assertEqual(content, "Hello external")

        // Second call should find existing
        let (store2, uuid2, isNew2) = try ExternalFileManager.openOrCreateCompanion(
            for: txtURL, content: "Hello external")
        store2.close()
        try assertTrue(!isNew2, "should not be new")
        try assertEqual(uuid, uuid2)
    }
}

func runRegistryManagerTests() {
    print("\nRegistryManagerTests:")

    test("upsert and find by UUID") {
        let uuid = UUID()
        let entry = RegistryEntry(
            jntPath: "/tmp/test.jnt", isCompanion: false, companionOriginalPath: nil,
            displayName: "Test", lastModifiedAt: "2024-01-01", parentUUID: nil,
            childUUIDs: [], sizeBytes: 100)
        try RegistryManager.upsert(uuid: uuid, entry: entry)

        let found = RegistryManager.findByUUID(uuid)
        try assertNotNil(found)
        try assertEqual(found?.displayName, "Test")
        try assertEqual(found?.jntPath, "/tmp/test.jnt")
    }

    test("find by original path") {
        let uuid = UUID()
        let entry = RegistryEntry(
            jntPath: "/tmp/companion.jnt", isCompanion: true,
            companionOriginalPath: "/tmp/original_\(uuid.uuidString).txt",
            displayName: "Original", lastModifiedAt: "2024-01-01",
            parentUUID: nil, childUUIDs: [], sizeBytes: 50)
        try RegistryManager.upsert(uuid: uuid, entry: entry)

        let result = RegistryManager.findByOriginalPath("/tmp/original_\(uuid.uuidString).txt")
        try assertNotNil(result)
        try assertEqual(result?.0, uuid)
    }

    test("update existing entry") {
        let uuid = UUID()
        var entry = RegistryEntry(
            jntPath: "/tmp/test2.jnt", isCompanion: false, companionOriginalPath: nil,
            displayName: "V1", lastModifiedAt: "2024-01-01", parentUUID: nil,
            childUUIDs: [], sizeBytes: 100)
        try RegistryManager.upsert(uuid: uuid, entry: entry)

        entry.displayName = "V2"
        entry.sizeBytes = 200
        try RegistryManager.upsert(uuid: uuid, entry: entry)

        let found = RegistryManager.findByUUID(uuid)
        try assertEqual(found?.displayName, "V2")
        try assertEqual(found?.sizeBytes, 200)
    }

    test("remove entry") {
        let uuid = UUID()
        let entry = RegistryEntry(
            jntPath: "/tmp/removeme.jnt", isCompanion: false, companionOriginalPath: nil,
            displayName: "Remove", lastModifiedAt: "2024-01-01", parentUUID: nil,
            childUUIDs: [], sizeBytes: 0)
        try RegistryManager.upsert(uuid: uuid, entry: entry)
        try RegistryManager.remove(uuid: uuid)
        let found = RegistryManager.findByUUID(uuid)
        try assertTrue(found == nil, "should be removed")
    }
}

func runSourceChainManagerTests() {
    print("\nSourceChainManagerTests:")

    test("no parent returns noParent") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "chain_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "root", uuid: UUID())
        defer { store.close() }

        let chain = SourceChainManager(fileStore: store)
        let resolution = try chain.resolveParent()
        if case .noParent = resolution {} else {
            throw AssertionError(description: "expected noParent, got \(resolution)")
        }
    }

    test("hasChildren returns true when children exist") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "chain_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "parent", uuid: UUID())
        defer { store.close() }

        let chain = SourceChainManager(fileStore: store)
        try assertTrue(!(try chain.hasChildren()), "should have no children initially")

        try store.addChild(uuid: UUID(), path: "/tmp/child.jnt",
                           forkTimestamp: Date(), forkSeq: 0)
        try assertTrue(try chain.hasChildren(), "should have children now")
    }

    test("parent info reads from metadata") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "chain_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let parentUUID = UUID()
        let store = try JNTFileStore.create(at: url, content: "child", uuid: UUID())
        defer { store.close() }

        try store.writeMetadata(key: "parent_uuid", value: parentUUID.uuidString)
        try store.writeMetadata(key: "parent_path", value: "/tmp/parent.jnt")

        let chain = SourceChainManager(fileStore: store)
        let info = try chain.parentInfo()
        try assertNotNil(info)
        try assertEqual(info?.uuid, parentUUID)
        try assertEqual(info?.path, "/tmp/parent.jnt")
    }

    test("resolve parent — unreachable when file missing") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "chain_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "child", uuid: UUID())
        defer { store.close() }

        let parentUUID = UUID()
        try store.writeMetadata(key: "parent_uuid", value: parentUUID.uuidString)
        try store.writeMetadata(key: "parent_path", value: "/tmp/nonexistent_\(UUID().uuidString).jnt")

        let chain = SourceChainManager(fileStore: store)
        let resolution = try chain.resolveParent()
        if case .unreachable(let uuid) = resolution {
            try assertEqual(uuid, parentUUID)
        } else {
            throw AssertionError(description: "expected unreachable, got \(resolution)")
        }
    }

    test("children info reads from children table") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "chain_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "parent", uuid: UUID())
        defer { store.close() }

        let child1 = UUID()
        let child2 = UUID()
        try store.addChild(uuid: child1, path: "/tmp/c1.jnt", forkTimestamp: Date(), forkSeq: 1)
        try store.addChild(uuid: child2, path: "/tmp/c2.jnt", forkTimestamp: Date(), forkSeq: 2)

        let chain = SourceChainManager(fileStore: store)
        let children = try chain.childrenInfo()
        try assertEqual(children.count, 2)
    }
}

func runCleanupManagerTests() {
    print("\nCleanupManagerTests:")

    test("clearAll and recreate") {
        try CleanupManager.clearAll()
        let fm = FileManager.default
        try assertTrue(fm.fileExists(atPath:
            ExternalFileManager.jettyNoteFolder.appendingPathComponent("companions").path),
            "companions dir should be recreated")
    }

    test("totalStorageBytes with no files") {
        try CleanupManager.clearAll()
        let bytes = try CleanupManager.totalStorageBytes()
        try assertEqual(bytes, 0)
    }
}

func runMidTreeEditTests() {
    print("\nMidTreeEditTests:")

    test("document with children — hasChildren is true") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "midtree_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "parent", uuid: UUID())
        defer { store.close() }

        try store.addChild(uuid: UUID(), path: "/tmp/child.jnt",
                           forkTimestamp: Date(), forkSeq: 0)

        let chain = SourceChainManager(fileStore: store)
        try assertTrue(try chain.hasChildren(), "should detect children")
    }

    test("document without children — hasChildren is false") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "midtree_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "leaf", uuid: UUID())
        defer { store.close() }

        let chain = SourceChainManager(fileStore: store)
        try assertTrue(!(try chain.hasChildren()), "should have no children")
    }
}
