import AppKit

public class EditorViewController: NSViewController, NSTextViewDelegate {
    public var textView: NSTextView!
    public weak var document: JNTDocument?
    public private(set) var jntTextStorage: JNTTextStorage?

    public override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]

        let contentSize = scrollView.contentSize
        let storage = JNTTextStorage()
        self.jntTextStorage = storage
        let textStorage: NSTextStorage = storage
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
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
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

    // MARK: - Markdown toggle

    public func toggleMarkdownRendering(_ enabled: Bool) {
        jntTextStorage?.markdownRenderingEnabled = enabled
        jntTextStorage?.invalidateAndReapplyStyles()
    }

    // MARK: - NSTextViewDelegate

    private var hasCheckedMidTree = false

    public func textDidChange(_ notification: Notification) {
        document?.content = textView.string
        document?.updateChangeCount(.changeDone)
        document?.autoSaveManager.documentContentDidChange()

        // One-time mid-tree edit check per session
        if !hasCheckedMidTree {
            hasCheckedMidTree = true
            document?.checkMidTreeEdit()
        }
    }
}
