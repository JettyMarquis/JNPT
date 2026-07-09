import AppKit

public class EditorViewController: NSViewController, NSTextViewDelegate {
    public var textView: NSTextView!
    public weak var document: JNTDocument?
    private var didApplyRestoredState = false

    private static let defaultFontSize: CGFloat = 28
    private static let fontSizeKey = "editorFontSize"
    private static let fontSizeStep: CGFloat = 2
    private static let fontSizeMin: CGFloat = 8
    private static let fontSizeMax: CGFloat = 72

    private var currentFontSize: CGFloat {
        let v = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        return v > 0 ? CGFloat(v) : Self.defaultFontSize
    }

    public override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: NSSize(
            width: contentSize.width,
            height: CGFloat.greatestFiniteMagnitude
        ))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: currentFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.allowsUndo = true
        // NOTE: levelsOfUndo is NOT configured here — `document` isn't set yet
        // at loadView() time, and per-document undo isolation (undoManager(for:)
        // below) means the manager to configure isn't known until then. See
        // editorDidBecomeActive().
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.delegate = self

        scrollView.documentView = textView
        self.view = scrollView
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        editorDidBecomeActive()
    }

    /// Full "this editor is now the one on screen" routine: content sync, the
    /// one-time restored cursor/scroll application, and making the text view
    /// first responder. Extracted from `viewDidAppear()` so a shared-window /
    /// multi-tab host (ShellWindowController, Phase 1+) can call it explicitly
    /// after manually mounting this editor's view — AppKit's automatic
    /// `viewWillAppear`/`viewDidAppear` firing on manual subview
    /// add/remove-via-containment is not something to rely on. `viewDidAppear()`
    /// itself still calls this so the existing single-window path (and
    /// SessionRestoreTests, which call `viewDidAppear()` directly) keeps working
    /// unchanged.
    func editorDidBecomeActive() {
        // Per-document undo isolation: NSDocument vends its own lazily-created
        // UndoManager (see undoManager(for:) below); configure it once here
        // rather than at loadView() time, when `document` isn't set yet. Safe
        // to repeat on every activation — setting levelsOfUndo doesn't reset
        // existing undo groups.
        document?.undoManager?.levelsOfUndo = 100
        if let content = document?.content, textView.string != content {
            textView.string = content
        }
        // Only on the very first activation (document just opened) — otherwise
        // switching tabs would yank the cursor/scroll back on every appear. Must
        // run after the string is set above: applying to stale (pre-content) text
        // would compute against the wrong length.
        if !didApplyRestoredState {
            didApplyRestoredState = true
            applyRestoredCursorAndScroll()
        }
        view.window?.makeFirstResponder(textView)
    }

    private func applyRestoredCursorAndScroll() {
        guard let doc = document else { return }
        let length = (textView.string as NSString).length
        if let cursor = doc.restoredCursor {
            let clamped = min(max(cursor, 0), length)
            textView.setSelectedRange(NSRange(location: clamped, length: 0))
        }
        if let scroll = doc.restoredScroll, let scrollView = textView.enclosingScrollView {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(scroll, 0)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    // MARK: - Font size

    @objc public func increaseFontSize(_ sender: Any?) {
        applyFontSize(min(currentFontSize + Self.fontSizeStep, Self.fontSizeMax))
    }

    @objc public func decreaseFontSize(_ sender: Any?) {
        applyFontSize(max(currentFontSize - Self.fontSizeStep, Self.fontSizeMin))
    }

    private func applyFontSize(_ size: CGFloat) {
        UserDefaults.standard.set(Double(size), forKey: Self.fontSizeKey)
        // Applying a font change while the user is mid-IME-composition would touch
        // the marked-text range and disrupt composition — the same bug class this
        // editor rebuild fixes. Defer until composition ends.
        guard !textView.hasMarkedText() else { return }
        let newFont = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        textView.font = newFont
        textView.typingAttributes[.font] = newFont
    }

    // MARK: - NSTextViewDelegate

    public func textDidChange(_ notification: Notification) {
        document?.content = textView.string
        document?.updateChangeCount(.changeDone)
        document?.autoSaveManager.documentContentDidChange()
    }

    /// Without this override, NSTextView resolves its undo manager through
    /// the responder chain to `window.undoManager` — harmless when every
    /// document has its own real window, but under the shared-window
    /// architecture (ShellWindowController) that would make every open tab
    /// share ONE undo stack, so ⌘Z on tab B could undo an edit made in tab A.
    /// NSDocument already vends its own lazily-created, per-document
    /// UndoManager — return that instead.
    public func undoManager(for view: NSTextView) -> UndoManager? {
        document?.undoManager
    }
}
