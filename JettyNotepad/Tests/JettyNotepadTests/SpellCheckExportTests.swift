import Foundation
import JettyNotepadKit

func runSpellCheckExportTests() {
    print("\n--- Spell Check / Export Tests ---")

    // MARK: displayNameFromContent (used for export filename)

    test("Export: displayNameFromContent trims leading whitespace") {
        let name = JNTFileStore.displayNameFromContent("   hello world")
        try assertTrue(!name.hasPrefix(" "), "Should not start with spaces: \(name)")
    }

    test("Export: displayNameFromContent uses first line") {
        let name = JNTFileStore.displayNameFromContent("First Line\nSecond Line")
        try assertTrue(name.contains("First"), "Should derive from first line, got: \(name)")
        try assertTrue(!name.contains("Second"), "Should not include second line, got: \(name)")
    }

    test("Export: displayNameFromContent empty content gives Untitled") {
        let name = JNTFileStore.displayNameFromContent("")
        try assertEqual(name, "Untitled")
    }

    test("Export: displayNameFromContent with only whitespace gives Untitled") {
        let name = JNTFileStore.displayNameFromContent("   \n   ")
        try assertEqual(name, "Untitled")
    }

    test("Export: displayNameFromContent caps length") {
        let long = String(repeating: "a", count: 200)
        let name = JNTFileStore.displayNameFromContent(long)
        try assertTrue(name.count <= 64, "Display name too long: \(name.count)")
    }

    test("Export: displayNameFromContent markdown heading stripped") {
        // First line may be a heading — the name should be usable as a filename
        let name = JNTFileStore.displayNameFromContent("# My Document Title")
        try assertTrue(!name.isEmpty, "Name should not be empty")
        // Name should not be just "#"
        try assertTrue(name != "#", "Name should not just be the hash: \(name)")
    }
}
