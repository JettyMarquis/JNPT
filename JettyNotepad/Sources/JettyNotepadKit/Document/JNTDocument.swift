import AppKit

public class JNTDocument: NSDocument {
    public var fileStore: JNTFileStore?
    public var content: String = ""
    public var lastSavedContent: String = ""
    public var fileUUID: UUID = UUID()
    public let autoSaveManager = AutoSaveManager()
    public var snapshotManager: SnapshotManager?
    private var isManualSave = false

    /// Cursor/scroll to apply once the editor mounts — from the .jnt file's last
    /// saved position (set in read(from:)), then possibly overridden by more
    /// recent in-session state from window restoration (see restoreState(with:)).
    public var restoredCursor: Int?
    public var restoredScroll: Double?

    // MARK: - NSDocument Overrides

    public override class var autosavesInPlace: Bool { true }
    public override class var autosavesDrafts: Bool { true }

    public override class var readableTypes: [String] {
        ["com.jettymarquis.jettynotepad.jnt"]
    }

    public override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        ["com.jettymarquis.jettynotepad.jnt"]
    }

    public override class func isNativeType(_ name: String) -> Bool {
        name == "com.jettymarquis.jettynotepad.jnt"
    }

    public override init() {
        super.init()
        autoSaveManager.document = self
    }

    // MARK: - Window Controllers

    public override func makeWindowControllers() {
        let proxy = DocumentProxyWindowController()
        addWindowController(proxy)
        ShellWindowController.shared.addTab(for: self, proxy: proxy)
        // Started here (not init) so the editor/window exist before the first
        // possible autosave fire — an autosave before the editor mounts would
        // persist cursor=0/scroll=0, discarding restored session state.
        autoSaveManager.start(interval: AutoSaveManager.configuredInterval())
    }

    /// All documents share the one real window owned by ShellWindowController
    /// (this document's own window controller is a windowless proxy) — Save/
    /// dirty-close sheets must attach there.
    public override var windowForSheet: NSWindow? {
        ShellWindowController.shared.window
    }

    // MARK: - Reading

    public override var fileURL: URL? {
        didSet { updateTabState() }
    }

    public override func read(from url: URL, ofType typeName: String) throws {
        fileStore?.close()
        let store = try JNTFileStore(url: url)
        let state = try store.readDocumentState()
        self.fileStore = store
        self.snapshotManager = SnapshotManager(fileStore: store)
        self.content = state.content
        self.lastSavedContent = state.content
        self.restoredCursor = state.cursorPosition
        self.restoredScroll = state.scrollPosition
        if let uuidStr = try store.readMetadata(key: "file_uuid"),
           let uuid = UUID(uuidString: uuidStr) {
            self.fileUUID = uuid
        }
    }

    public override func revert(toContentsOf url: URL, ofType typeName: String) throws {
        try super.revert(toContentsOf: url, ofType: typeName)
        editorViewController?.textView.string = content
        undoManager?.removeAllActions()
        updateTabState()
    }

    // MARK: - Writing

    public override func write(to url: URL, ofType typeName: String) throws {
        if fileStore == nil {
            // First save of a new document
            fileStore = try JNTFileStore.create(at: url, content: content, uuid: fileUUID)
            snapshotManager = SnapshotManager(fileStore: fileStore!)
        } else if fileStore!.url != url {
            // Save As — new file, fresh UUID, no generation links
            let newUUID = UUID()
            let newStore = try JNTFileStore.create(at: url, content: content, uuid: newUUID)
            fileStore?.close()
            fileStore = newStore
            snapshotManager = SnapshotManager(fileStore: newStore)
            fileUUID = newUUID
        } else {
            // Regular save — snapshot if content changed. The snapshot insert and
            // content update must commit atomically: a crash between them would
            // leave a snapshot whose reverse diff assumes content that was never
            // persisted, corrupting the chain on reconstruction. The 100-snapshot
            // cap is enforced solely by the `limit_snapshots` SQLite trigger (FIFO
            // by seq) — see JNTSchema.swift.
            try fileStore!.db.inTransaction {
                if content != lastSavedContent {
                    let snapshotType = isManualSave ? "manualSave" : "autoSave"
                    try snapshotManager?.createSnapshot(
                        previousContent: lastSavedContent,
                        currentContent: content,
                        type: snapshotType,
                        editSummary: nil
                    )
                }
                try fileStore!.saveContent(
                    content,
                    cursor: editorViewController?.textView.selectedRange().location ?? 0,
                    scroll: Double(editorViewController?.textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0)
                )
            }
        }
        lastSavedContent = content
        isManualSave = false
        updateTabState()
    }

    public override func save(to url: URL, ofType typeName: String,
                              for saveOperation: NSDocument.SaveOperationType,
                              completionHandler: @escaping (Error?) -> Void) {
        if saveOperation == .saveOperation {
            isManualSave = true
        }
        super.save(to: url, ofType: typeName, for: saveOperation) { error in
            if error == nil {
                self.lastSavedContent = self.content
                self.updateTabState()
            }
            self.isManualSave = false
            completionHandler(error)
        }
    }

    // MARK: - Change Tracking

    public override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        updateTabState()
    }

    // MARK: - Helpers

    /// Stored (not derived from `windowControllers.first?.contentViewController`)
    /// so a future shared-window/multi-tab host can assign this directly when it
    /// creates the editor for this document, without that editor needing to be
    /// literally the window's root contentViewController.
    public weak var editorViewController: EditorViewController?

    private func updateTabState() {
        ShellWindowController.shared.refreshTab(for: self)
    }
}
