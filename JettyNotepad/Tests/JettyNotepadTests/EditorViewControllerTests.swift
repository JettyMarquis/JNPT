import Foundation
import AppKit
import JettyNotepadKit

// Regression guard for the 跳行错行 (line jump/scramble) bug: JNTTextStorage's
// full-document processEditing() invalidation was the root cause. This asserts
// the production editor wiring uses a plain NSTextStorage, not that subclass —
// exercising the real EditorViewController.loadView() path, not a parallel
// reimplementation, so a future re-wiring of JNTTextStorage into the live editor
// would fail this test.
func runEditorViewControllerTests() {
    print("\nEditorViewControllerTests:")

    test("production editor uses plain NSTextStorage, not JNTTextStorage") {
        let vc = EditorViewController(nibName: nil, bundle: nil)
        _ = vc.view // triggers loadView()

        guard let storage = vc.textView.textStorage else {
            throw AssertionError(description: "textView.textStorage is nil after loadView()")
        }
        // NSTextStorage() returns an AppKit class-cluster instance (e.g.
        // NSConcreteTextStorage), never literally `NSTextStorage.self` — so assert
        // the negative: it must not be our custom full-document-invalidating subclass.
        try assertTrue(
            !(storage is JNTTextStorage),
            "editor textStorage is \(type(of: storage)), must not be JNTTextStorage"
        )
    }

    test("editor textView has minSize/maxSize configured for scroll growth") {
        let vc = EditorViewController(nibName: nil, bundle: nil)
        _ = vc.view

        try assertTrue(vc.textView.isVerticallyResizable, "textView must be vertically resizable")
        try assertEqual(vc.textView.maxSize.height, CGFloat.greatestFiniteMagnitude)
    }
}
