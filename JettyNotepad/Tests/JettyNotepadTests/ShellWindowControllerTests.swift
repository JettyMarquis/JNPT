import Foundation
import AppKit
import JettyNotepadKit

// Uses a FRESH ShellWindowController() instance per test (never `.shared`) so
// tabs don't leak across test cases sharing one process — `swift run
// JettyNotepadTests` runs every test sequentially in one process, and
// `.shared` is a genuine process-wide singleton.
func runShellWindowControllerTests() {
    print("\nShellWindowControllerTests:")

    func registerTab(_ shell: ShellWindowController, content: String = "") -> JNTDocument {
        let doc = JNTDocument()
        doc.content = content
        let proxy = DocumentProxyWindowController()
        doc.addWindowController(proxy)
        shell.addTab(for: doc, proxy: proxy)
        return doc
    }

    test("addTab appends and selects the new tab") {
        let shell = ShellWindowController()
        let doc = registerTab(shell, content: "hello")
        try assertEqual(shell.tabs.count, 1)
        try assertEqual(shell.selectedIndex, 0)
        try assertTrue(shell.activeDocument === doc)
        try assertNotNil(shell.activeEditor)
    }

    test("adding a second tab selects it while the first stays in the array") {
        let shell = ShellWindowController()
        let doc1 = registerTab(shell, content: "one")
        let doc2 = registerTab(shell, content: "two")
        try assertEqual(shell.tabs.count, 2)
        try assertEqual(shell.selectedIndex, 1)
        try assertTrue(shell.activeDocument === doc2)
        try assertTrue(shell.tabs[0].document === doc1)
    }

    test("selectTab(at:) switches the active document back") {
        let shell = ShellWindowController()
        let doc1 = registerTab(shell, content: "one")
        _ = registerTab(shell, content: "two")
        shell.selectTab(at: 0)
        try assertEqual(shell.selectedIndex, 0)
        try assertTrue(shell.activeDocument === doc1)
    }

    test("selectTab(for:) finds and selects the tab by document identity") {
        let shell = ShellWindowController()
        let doc1 = registerTab(shell, content: "one")
        _ = registerTab(shell, content: "two")
        shell.selectTab(for: doc1)
        try assertTrue(shell.activeDocument === doc1)
    }

    test("each document gets its own UndoManager instance (no cross-tab bleed)") {
        let shell = ShellWindowController()
        let doc1 = registerTab(shell, content: "one")
        let doc2 = registerTab(shell, content: "two")
        let um1 = doc1.editorViewController?.undoManager(for: NSTextView())
        let um2 = doc2.editorViewController?.undoManager(for: NSTextView())
        try assertNotNil(um1)
        try assertNotNil(um2)
        try assertTrue(um1 !== um2, "each document must vend a distinct undo manager")
        try assertTrue(um1 === doc1.undoManager, "must be NSDocument's own per-document manager")
    }

    test("refreshTab updates window.title only for the active tab, not a background one") {
        let shell = ShellWindowController()
        let doc1 = registerTab(shell, content: "Foo document")
        let doc2 = registerTab(shell, content: "Bar document") // now active
        let titleBeforeBackgroundEdit = shell.window?.title

        doc1.content = "Foo document changed" // background tab edit
        shell.refreshTab(for: doc1)

        try assertTrue(shell.window?.title == titleBeforeBackgroundEdit,
                       "a background tab's state change must not clobber the active tab's window title")
        try assertTrue(shell.tabs[0].isModified, "the background tab's own dirty state should still update")
        _ = doc2
    }

    test("validateMenuItem disables Save for a clean, previously-saved document") {
        let shell = ShellWindowController()
        let doc = registerTab(shell, content: "clean")
        // Simulate "previously saved": a real fileURL, and no pending edits.
        // (`fileURL == nil` alone would make Save correctly always-enabled —
        // see the "never saved" test below — so that must NOT be the case here.)
        doc.fileURL = URL(fileURLWithPath: "/tmp/fake_saved_\(UUID().uuidString).jnt")
        doc.updateChangeCount(.changeCleared)
        let item = NSMenuItem(title: "Save", action: #selector(ShellWindowController.saveActiveDocument(_:)), keyEquivalent: "")
        try assertTrue(!shell.validateMenuItem(item), "Save should be disabled on an unmodified, previously-saved document")
    }

    test("validateMenuItem enables Save for a document with no file yet (never saved)") {
        let shell = ShellWindowController()
        _ = registerTab(shell, content: "new document, never saved")
        let item = NSMenuItem(title: "Save", action: #selector(ShellWindowController.saveActiveDocument(_:)), keyEquivalent: "")
        try assertTrue(shell.validateMenuItem(item), "a never-saved document should always be able to Save")
    }

    test("validateMenuItem disables Revert to Saved when the document has no file") {
        let shell = ShellWindowController()
        _ = registerTab(shell, content: "untitled")
        let item = NSMenuItem(title: "Revert to Saved", action: #selector(ShellWindowController.revertActiveDocument(_:)), keyEquivalent: "")
        try assertTrue(!shell.validateMenuItem(item), "Revert must be disabled with no saved file to revert to")
    }
}
