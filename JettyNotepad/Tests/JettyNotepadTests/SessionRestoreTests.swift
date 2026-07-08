import Foundation
import AppKit
import JettyNotepadKit

func runSessionRestoreTests() {
    print("\nSessionRestoreTests:")

    func editorViewController(for doc: JNTDocument) throws -> EditorViewController {
        doc.makeWindowControllers()
        guard let vc = doc.windowControllers.first?.contentViewController as? EditorViewController else {
            throw AssertionError(description: "no EditorViewController from makeWindowControllers()")
        }
        _ = vc.view // force loadView()
        return vc
    }

    test("read(from:) populates restoredCursor/restoredScroll from the .jnt file") {
        let url = URL(fileURLWithPath: NSTemporaryDirectory() + "restore_\(UUID().uuidString).jnt")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try JNTFileStore.create(at: url, content: "hello world", uuid: UUID())
        try store.saveContent("hello world", cursor: 6, scroll: 42.5)
        store.close()

        let doc = JNTDocument()
        try doc.read(from: url, ofType: "com.jettymarquis.jettynotepad.jnt")
        try assertEqual(doc.restoredCursor, 6)
        try assertNotNil(doc.restoredScroll)
        try assertTrue(abs((doc.restoredScroll ?? -1) - 42.5) < 0.001, "scroll mismatch")
    }

    // NOTE: encodeRestorableState/restoreState round-tripping through a hand-built
    // NSKeyedArchiver/NSKeyedUnarchiver pair is NOT tested here — NSDocument's
    // restorable-state machinery asserts on `requiresSecureCoding` internally
    // (NSPersistentUIUnarchiver expects the real window-restoration coder) and
    // aborts the process outside that context. The decode logic itself is a few
    // guarded primitive reads (see restoreState(with:)); the read(from:) and
    // viewDidAppear tests below cover the paths that matter in practice.

    test("viewDidAppear clamps an out-of-range restored cursor instead of crashing") {
        let doc = JNTDocument()
        doc.content = "short"
        doc.restoredCursor = 9999
        let editorVC = try editorViewController(for: doc)

        editorVC.viewDidAppear() // must not throw/crash on the out-of-range cursor
        try assertEqual(editorVC.textView.selectedRange().location, (doc.content as NSString).length)
    }

    test("viewDidAppear applies the restored cursor only on first appearance") {
        let doc = JNTDocument()
        doc.content = "hello world"
        doc.restoredCursor = 5
        let editorVC = try editorViewController(for: doc)

        editorVC.viewDidAppear()
        try assertEqual(editorVC.textView.selectedRange().location, 5)

        // Simulate the user moving the cursor, then switching tabs back (another
        // appear) — the restored position must not be reapplied and yank it back.
        editorVC.textView.setSelectedRange(NSRange(location: 0, length: 0))
        editorVC.viewDidAppear()
        try assertEqual(editorVC.textView.selectedRange().location, 0)
    }
}
