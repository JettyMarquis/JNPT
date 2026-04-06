import Foundation
import JettyNotepadKit

if CommandLine.arguments.contains("--gate") {
    // Phase gate: create a .jnt for sqlite3 verification
    let path = "/tmp/jnpt_gate1.jnt"
    try? FileManager.default.removeItem(atPath: path)
    let url = URL(fileURLWithPath: path)
    let store = try JNTFileStore.create(at: url, content: "Gate test content", uuid: UUID())
    store.close()
    print("GATE_FILE=\(path)")
    exit(0)
}

if CommandLine.arguments.contains("--gate2") {
    // Phase 2 gate: create parent/child .jnt pair
    let parentPath = "/tmp/jnpt_parent.jnt"
    let childPath = "/tmp/jnpt_child.jnt"
    try? FileManager.default.removeItem(atPath: parentPath)
    try? FileManager.default.removeItem(atPath: childPath)

    let parentUUID = UUID()
    let parentStore = try JNTFileStore.create(
        at: URL(fileURLWithPath: parentPath), content: "Parent", uuid: parentUUID)
    let sm = SnapshotManager(fileStore: parentStore)

    // Create snapshot history
    try sm.createSnapshot(previousContent: "Parent", currentContent: "Parent v2",
                          type: "manualSave", editSummary: nil)
    try parentStore.saveContent("Parent v2", cursor: 0, scroll: 0)

    // Fork
    try sm.createSnapshot(previousContent: "Parent v2", currentContent: "Parent v2",
                          type: "forkPoint", editSummary: nil)
    let forkSeq = (try parentStore.readSnapshotManifest()).first?.seq ?? 0

    let childUUID = UUID()
    try parentStore.addChild(uuid: childUUID, path: childPath,
                             forkTimestamp: Date(), forkSeq: forkSeq)

    let childStore = try JNTFileStore.create(
        at: URL(fileURLWithPath: childPath), content: "Parent v2", uuid: childUUID)
    try childStore.writeMetadata(key: "parent_uuid", value: parentUUID.uuidString)
    try childStore.writeMetadata(key: "parent_path", value: parentPath)

    parentStore.close()
    childStore.close()
    print("PARENT=\(parentPath)")
    print("CHILD=\(childPath)")
    exit(0)
}

print("=== JettyNotepad Test Suite ===\n")

// Phase 1 tests
runSQLiteDatabaseTests()
runJNTSchemaTests()
runJNTFileStoreTests()

// Phase 2 tests
runDiffMatchPatchTests()
runSnapshotManagerTests()
runSaveAsTests()

printSummary()
