import Foundation
import AppKit
import JettyNotepadKit

// Exercises the same shouldChangeText+replaceCharacters+didChangeText idiom used by
// HistoryPanelController.restoreSnapshot, without invoking the actual NSAlert-gated
// UI path (which would block a headless test run). Confirms: NSTextStorage's UTF-16
// length (not Swift String.count) must be used for the pre-replacement range, the
// replacement is a single undoable step, and CJK/emoji content round-trips correctly.
func runHistoryRestoreTests() {
    print("\nHistoryRestoreTests:")

    // NSTextView.undoManager resolves via its window (allowsUndo asks the window
    // for one), so the view must actually be hosted in a window — a bare
    // `_ = vc.view` (no window) leaves undoManager nil.
    func makeTextView(initial: String) -> NSTextView {
        let vc = EditorViewController(nibName: nil, bundle: nil)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentViewController = vc
        vc.textView.string = initial
        return vc.textView
    }

    test("restore replacement uses NSString length, not Swift String.count, for CJK content") {
        let textView = makeTextView(initial: "你好世界")
        guard let storage = textView.textStorage else { throw AssertionError(description: "no textStorage") }
        let oldFullRange = NSRange(location: 0, length: storage.length)
        try assertEqual(oldFullRange.length, (textView.string as NSString).length)

        let newContent = "こんにちは 🎉🎉"
        try assertTrue(textView.shouldChangeText(in: oldFullRange, replacementString: newContent))
        storage.replaceCharacters(in: oldFullRange, with: newContent)
        textView.didChangeText()

        try assertEqual(textView.string, newContent)
    }

    test("restore replacement is a single undoable step") {
        let textView = makeTextView(initial: "original content")
        guard let storage = textView.textStorage else { throw AssertionError(description: "no textStorage") }
        let oldFullRange = NSRange(location: 0, length: storage.length)

        try assertTrue(textView.shouldChangeText(in: oldFullRange, replacementString: "restored content"))
        storage.replaceCharacters(in: oldFullRange, with: "restored content")
        textView.didChangeText()
        try assertEqual(textView.string, "restored content")

        guard let undoManager = textView.undoManager else { throw AssertionError(description: "no undoManager") }
        try assertTrue(undoManager.canUndo, "replacement must register a single undo step")
        undoManager.undo()
        try assertEqual(textView.string, "original content")
    }

    test("replacing with emoji-containing content does not mis-range") {
        let textView = makeTextView(initial: "before 🚀 text")
        guard let storage = textView.textStorage else { throw AssertionError(description: "no textStorage") }
        let oldFullRange = NSRange(location: 0, length: storage.length)
        let newContent = "after 🎈🎈🎈 done"
        try assertTrue(textView.shouldChangeText(in: oldFullRange, replacementString: newContent))
        storage.replaceCharacters(in: oldFullRange, with: newContent)
        textView.didChangeText()
        try assertEqual(textView.string, newContent)
    }
}
