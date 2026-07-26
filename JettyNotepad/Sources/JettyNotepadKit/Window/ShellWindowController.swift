import AppKit

/// The one real NSWindow shared by every open document/tab. Each `JNTDocument`
/// registers a windowless `DocumentProxyWindowController` with itself (see
/// `JNTDocument.makeWindowControllers()`) and is then handed to this
/// controller's `addTab(for:proxy:)` to become a tab.
public final class ShellWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    /// Lazily created on first access (Swift `static let` is already
    /// thread-safe/lazy) — created no earlier than the first document's
    /// `makeWindowControllers()`, which only ever runs on the main thread
    /// after the app has started launching.
    public static let shared = ShellWindowController()

    private static let restorableSessionKey = "jnt.shell.restorableSession"
    private static let windowIdentifier = NSUserInterfaceItemIdentifier("com.jettymarquis.jettynotepad.shell")

    public private(set) var tabs: [TabItem] = []
    public private(set) var selectedIndex: Int = -1
    private var contentVC: ShellContentViewController!

    public var activeDocument: JNTDocument? {
        tabs.indices.contains(selectedIndex) ? tabs[selectedIndex].document : nil
    }

    public var activeEditor: EditorViewController? {
        tabs.indices.contains(selectedIndex) ? tabs[selectedIndex].editor : nil
    }

    /// Public, not private: tests construct independent instances via this
    /// initializer (NOT `.shared`) so tabs don't leak across test cases —
    /// `swift run JettyNotepadTests` runs every test sequentially in one
    /// process, and the existing suite (AutoSaveManagerTests,
    /// SQLiteDatabaseTests) already isolates per-test state for exactly this
    /// reason.
    public init() {
        let vc = ShellContentViewController()
        contentVC = vc
        let window = Self.makeWindow()
        super.init(window: window)
        window.contentViewController = vc
        window.delegate = self
        window.identifier = Self.windowIdentifier
        window.isRestorable = true
        window.restorationClass = ShellWindowController.self
    }

    required init?(coder: NSCoder) {
        fatalError("ShellWindowController does not support NSCoding init")
    }

    private static func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.setFrameAutosaveName("JettyNotepadShellWindow")
        window.minSize = NSSize(width: 400, height: 300)
        window.title = "Untitled"
        return window
    }

    // MARK: - Tab management

    /// Called from `JNTDocument.makeWindowControllers()` after it has already
    /// created and registered `proxy` via `addWindowController(proxy)`.
    @discardableResult
    public func addTab(for document: JNTDocument, proxy: DocumentProxyWindowController) -> TabItem {
        let editor = EditorViewController()
        editor.document = document
        // Force loadView() immediately, even for a tab that isn't the initial
        // selection — otherwise `editor.textView` (implicitly-unwrapped) stays
        // nil until first activation, and autosave reading
        // `editorViewController?.textView.selectedRange()` for a
        // never-yet-shown background tab would crash on the force-unwrap.
        _ = editor.view
        document.editorViewController = editor

        let item = TabItem(document: document, editor: editor, proxy: proxy,
                           displayName: JNTFileStore.displayNameFromContent(document.content),
                           isModified: false)
        tabs.append(item)
        selectTab(at: tabs.count - 1)
        return item
    }

    public func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        if tabs.indices.contains(selectedIndex), selectedIndex != index {
            let outgoing = tabs[selectedIndex]
            // Treat "this tab is being deselected" as its focus-loss trigger —
            // under one shared window, windowDidResignKey no longer fires per
            // document on tab switch (the window stays key).
            outgoing.document.autoSaveManager.documentDidLoseFocus()
            contentVC.unmount(outgoing.editor)
        }
        selectedIndex = index
        let incoming = tabs[index]
        contentVC.mount(incoming.editor)
        incoming.editor.editorDidBecomeActive()
        refreshTab(for: incoming.document)
    }

    /// Reselects the tab for `document` without touching any other tab's
    /// state. Used when NSDocumentController resolves File > Open (or
    /// Open Recent, or a Finder double-click) to an ALREADY-open document —
    /// it fronts the shared window via `DocumentProxyWindowController.
    /// showWindow(_:)` but has no notion of tabs on its own.
    public func selectTab(for document: JNTDocument) {
        guard let idx = tabs.firstIndex(where: { $0.document === document }) else { return }
        selectTab(at: idx)
    }

    public func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        let item = tabs[index]
        // Guards against a second close request for the same tab landing
        // while an earlier one's async save-sheet is still showing (e.g.
        // double-clicking the close button, or ⌘W while the sheet is up).
        guard !item.isClosing else { return }
        item.isClosing = true
        item.document.canClose(
            withDelegate: self,
            shouldClose: #selector(tabCloseCompleted(_:shouldClose:contextInfo:)),
            contextInfo: Unmanaged.passRetained(item).toOpaque()
        )
    }

    @objc private func tabCloseCompleted(_ document: NSDocument, shouldClose: Bool,
                                         contextInfo: UnsafeMutableRawPointer?) {
        guard let ptr = contextInfo else { return }
        let item = Unmanaged<TabItem>.fromOpaque(ptr).takeRetainedValue()
        guard shouldClose else {
            item.isClosing = false
            return
        }
        guard let jntDoc = document as? JNTDocument else { return }
        // Stop autosave BEFORE close(): otherwise a timer landing between the
        // user's "Don't Save" confirmation and actual teardown could write
        // the just-discarded edits back to disk, silently defeating "Don't
        // Save".
        jntDoc.autoSaveManager.stop()
        jntDoc.removeWindowController(item.proxy)
        removeTab(item)
        jntDoc.close()
        if tabs.isEmpty {
            openBlankUntitledTab()
        }
    }

    private func removeTab(_ item: TabItem) {
        guard let idx = tabs.firstIndex(where: { $0 === item }) else { return }
        let wasActive = (idx == selectedIndex)
        if wasActive {
            contentVC.unmount(item.editor)
        }
        tabs.remove(at: idx)

        if idx < selectedIndex {
            selectedIndex -= 1
        }

        if wasActive {
            selectedIndex = -1
            if !tabs.isEmpty {
                selectTab(at: min(idx, tabs.count - 1))
            }
        }
        // If the removed tab wasn't active, `selectedIndex` (already adjusted
        // above if needed) still correctly points at the still-mounted active
        // tab — no reselect needed, and re-selecting it would needlessly
        // re-run addChild/mount on an already-mounted editor.
    }

    private func openBlankUntitledTab() {
        NSDocumentController.shared.newDocument(nil)
    }

    /// Recomputes a tab's display name/dirty state; syncs `window.title` and
    /// `window.representedURL` ONLY when `document` is the currently active
    /// tab (a background tab's state change must never clobber the window
    /// chrome for whatever tab the user is actually looking at).
    public func refreshTab(for document: JNTDocument) {
        guard let item = tabs.first(where: { $0.document === document }) else { return }
        let name: String
        if let displayName = try? document.fileStore?.readMetadata(key: "display_name") {
            name = displayName
        } else {
            name = JNTFileStore.displayNameFromContent(document.content)
        }
        item.displayName = name
        item.isModified = document.content != document.lastSavedContent

        if document === activeDocument {
            let state: TabState = item.isModified ? .modified : .saved
            window?.title = TabStateManager.label(baseName: name, state: state)
            window?.representedURL = document.fileURL
        }
    }

    // MARK: - Window close (all tabs)

    private final class WindowCloseChainContext {
        let index: Int
        let completion: (Bool) -> Void
        init(index: Int, completion: @escaping (Bool) -> Void) {
            self.index = index
            self.completion = completion
        }
    }

    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeAllTabsSequentially(index: 0) { [weak self] allowed in
            guard allowed, let self = self else { return }
            for item in self.tabs {
                item.document.autoSaveManager.stop()
                item.document.removeWindowController(item.proxy)
                item.document.close()
            }
            self.tabs.removeAll()
            self.selectedIndex = -1
            sender.close()
        }
        // The async chain above decides whether/when the window actually
        // closes; a single sheet-bearing window can't present N confirmation
        // sheets at once, so tabs must be confirmed one at a time.
        return false
    }

    private func closeAllTabsSequentially(index: Int, completion: @escaping (Bool) -> Void) {
        guard index < tabs.count else { completion(true); return }
        let ctx = WindowCloseChainContext(index: index, completion: completion)
        tabs[index].document.canClose(
            withDelegate: self,
            shouldClose: #selector(windowCloseChainCompleted(_:shouldClose:contextInfo:)),
            contextInfo: Unmanaged.passRetained(ctx).toOpaque()
        )
    }

    @objc private func windowCloseChainCompleted(_ document: NSDocument, shouldClose: Bool,
                                                 contextInfo: UnsafeMutableRawPointer?) {
        guard let ptr = contextInfo else { return }
        let ctx = Unmanaged<WindowCloseChainContext>.fromOpaque(ptr).takeRetainedValue()
        guard shouldClose else {
            ctx.completion(false) // any Cancel aborts the whole window close
            return
        }
        closeAllTabsSequentially(index: ctx.index + 1, completion: ctx.completion)
    }

    // MARK: - File menu forwarding (see MenuBuilder — explicit target, not nil-target)

    @objc public func saveActiveDocument(_ sender: Any?) {
        activeDocument?.save(sender)
    }

    @objc public func saveActiveDocumentAs(_ sender: Any?) {
        activeDocument?.saveAs(sender)
    }

    @objc public func revertActiveDocument(_ sender: Any?) {
        activeDocument?.revertToSaved(sender)
    }

    @objc public func printActiveDocument(_ sender: Any?) {
        activeDocument?.printDocument(sender)
    }

    @objc public func closeActiveTab(_ sender: Any?) {
        guard selectedIndex >= 0 else { return }
        closeTab(at: selectedIndex)
    }

    /// Restores the enabled/disabled logic NSDocument's own nil-target
    /// resolution used to provide for free (e.g. "Revert to Saved" must be
    /// disabled for a document with no saved file, or "Save" for a clean
    /// document) — lost once these actions target this class explicitly
    /// instead of routing to the document via the responder chain.
    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let doc = activeDocument else { return false }
        switch menuItem.action {
        case #selector(saveActiveDocument(_:)):
            return doc.isDocumentEdited || doc.fileURL == nil
        case #selector(saveActiveDocumentAs(_:)):
            return true
        case #selector(revertActiveDocument(_:)):
            return doc.fileURL != nil && doc.isDocumentEdited
        case #selector(printActiveDocument(_:)):
            return true
        case #selector(closeActiveTab(_:)):
            return true
        default:
            return true
        }
    }

    // MARK: - Session restoration (replaces the per-document mechanism that
    // used to live on JNTDocument — see RestorableSession.swift for the
    // testable pure-data half of this)

    public override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        let kinds = tabs.compactMap { Self.tabKind(for: $0.document) }
        let session = RestorableSession(tabs: kinds, selectedIndex: selectedIndex)
        if let data = try? JSONEncoder().encode(session) {
            coder.encode(data as NSData, forKey: Self.restorableSessionKey)
        }
    }

    public override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        guard let data = coder.decodeObject(of: NSData.self, forKey: Self.restorableSessionKey) as Data?,
              let session = try? JSONDecoder().decode(RestorableSession.self, from: data),
              !session.tabs.isEmpty else { return }
        restoreNext(session.tabs, index: 0, target: session.selectedIndex)
    }

    private static func tabKind(for document: JNTDocument) -> RestorableSession.TabKind? {
        let isDirty = document.content != document.lastSavedContent
        if isDirty, let draftURL = document.autosavedContentsFileURL {
            let cursor = document.editorViewController?.textView.selectedRange().location ?? 0
            let scrollY = document.editorViewController?.textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
            return .draft(autosaveURL: draftURL, cursor: cursor, scroll: Double(scrollY))
        }
        if let url = document.fileURL {
            return .saved(url: url)
        }
        return nil // never-saved, no autosave draft yet — nothing durable to restore
    }

    private func restoreNext(_ kinds: [RestorableSession.TabKind], index: Int, target: Int) {
        guard index < kinds.count else {
            let finalIndex = RestorableSession.clampedIndex(target, tabCount: tabs.count)
            if tabs.indices.contains(finalIndex) { selectTab(at: finalIndex) }
            return
        }
        restoreTab(kind: kinds[index]) { [weak self] _ in
            self?.restoreNext(kinds, index: index + 1, target: target)
        }
    }

    private func restoreTab(kind: RestorableSession.TabKind, completion: @escaping (Bool) -> Void) {
        switch kind {
        case .saved(let url):
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { doc, _, error in
                completion(doc != nil && error == nil)
            }
        case .draft(let autosaveURL, let cursor, let scroll):
            do {
                let jntDoc = JNTDocument()
                try jntDoc.read(from: autosaveURL, ofType: "com.jettymarquis.jettynotepad.jnt")
                jntDoc.fileURL = nil // still untitled — autosaveURL is just where the draft is parked
                jntDoc.autosavedContentsFileURL = autosaveURL
                jntDoc.restoredCursor = cursor
                jntDoc.restoredScroll = scroll
                NSDocumentController.shared.addDocument(jntDoc)
                jntDoc.makeWindowControllers()
                completion(true)
            } catch {
                completion(false)
            }
        }
    }
}

// MARK: - NSWindowRestoration

extension ShellWindowController: NSWindowRestoration {
    public static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier,
                                     state: NSCoder,
                                     completionHandler: @escaping (NSWindow?, Error?) -> Void) {
        // There is only ever one shell window; accessing `.shared` here
        // lazily creates it if this is the very first touch (e.g. state
        // restoration racing document-open at launch).
        completionHandler(ShellWindowController.shared.window, nil)
    }
}
