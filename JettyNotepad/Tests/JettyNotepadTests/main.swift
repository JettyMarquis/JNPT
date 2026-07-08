import Foundation
import JettyNotepadKit

if CommandLine.arguments.contains("--gate") {
    let path = "/tmp/jnpt_gate1.jnt"
    try? FileManager.default.removeItem(atPath: path)
    let url = URL(fileURLWithPath: path)
    let store = try JNTFileStore.create(at: url, content: "Gate test content", uuid: UUID())
    store.close()
    print("GATE_FILE=\(path)")
    exit(0)
}

if CommandLine.arguments.contains("--gate2") {
    let parentPath = "/tmp/jnpt_parent.jnt"
    try? FileManager.default.removeItem(atPath: parentPath)
    let parentUUID = UUID()
    let parentStore = try JNTFileStore.create(
        at: URL(fileURLWithPath: parentPath), content: "Parent", uuid: parentUUID)
    let sm = SnapshotManager(fileStore: parentStore)
    try sm.createSnapshot(previousContent: "Parent", currentContent: "Parent v2",
                          type: "manualSave", editSummary: nil)
    try parentStore.saveContent("Parent v2", cursor: 0, scroll: 0)
    parentStore.close()
    print("PARENT=\(parentPath)")
    exit(0)
}

print("=== JettyNotepad Test Suite ===\n")

runMarkdownTests()
runSpellCheckExportTests()
runEditorViewControllerTests()

runSQLiteDatabaseTests()
runJNTSchemaTests()
runJNTFileStoreTests()
runAutoSaveManagerTests()

runDiffMatchPatchTests()
runSnapshotManagerTests()
runSaveAsTests()
runHistoryRestoreTests()
runSessionRestoreTests()

printSummary()
