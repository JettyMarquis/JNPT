import Foundation
import JettyNotepadKit

if CommandLine.arguments.contains("--gate") {
    // Phase 1 gate: create a .jnt and print its path for sqlite3 verification
    let path = "/tmp/jnpt_gate1.jnt"
    try? FileManager.default.removeItem(atPath: path)
    let url = URL(fileURLWithPath: path)
    let store = try JNTFileStore.create(at: url, content: "Gate test content", uuid: UUID())
    store.close()
    print("GATE_FILE=\(path)")
    exit(0)
}

print("=== JettyNotepad Test Suite ===\n")

runSQLiteDatabaseTests()
runJNTSchemaTests()
runJNTFileStoreTests()

printSummary()
