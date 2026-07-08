import AppKit

public class EditorViewController: NSViewController, NSTextViewDelegate {
    public var textView: NSTextView!
    public weak var document: JNTDocument?

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
        textView.undoManager?.levelsOfUndo = 100
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
        if let content = document?.content, textView.string != content {
            textView.string = content
        }
        view.window?.makeFirstResponder(textView)
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
}
