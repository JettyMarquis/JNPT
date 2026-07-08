import AppKit

public class JNTDocument: NSDocument {
    public var fileStore: JNTFileStore?
    public var content: String = ""
    public var lastSavedContent: String = ""
    public var fileUUID: UUID = UUID()
    public let autoSaveManager = AutoSaveManager()
    public var snapshotManager: SnapshotManager?
    private var tabStateManager: TabStateManager?
    private var isManualSave = false

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
        let wc = JNTWindowController()
        addWindowController(wc)
        if let editorVC = wc.contentViewController as? EditorViewController {
            editorVC.document = self
        }
        if let window = wc.window {
            tabStateManager = TabStateManager(window: window)
            updateTabState()
        }
        // Started here (not init) so the editor/window exist before the first
        // possible autosave fire — an autosave before the editor mounts would
        // persist cursor=0/scroll=0, discarding restored session state.
        autoSaveManager.start(interval: AutoSaveManager.configuredInterval())
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

    // MARK: - Session Restoration

    public override func encodeRestorableState(with coder: NSCoder) {
        super.encodeRestorableState(with: coder)
        coder.encode(content, forKey: "jnt.unsavedContent")
        let cursorPos = editorViewController?.textView.selectedRange().location ?? 0
        coder.encode(cursorPos, forKey: "jnt.cursorPos")
    }

    public override func restoreState(with coder: NSCoder) {
        super.restoreState(with: coder)
        if let restored = coder.decodeObject(forKey: "jnt.unsavedContent") as? String {
            content = restored
        }
    }

    // MARK: - Helpers

    var editorViewController: EditorViewController? {
        windowControllers.first?.contentViewController as? EditorViewController
    }

    private func updateTabState() {
        let name: String
        if let displayName = try? fileStore?.readMetadata(key: "display_name") {
            name = displayName
        } else {
            name = JNTFileStore.displayNameFromContent(content)
        }
        // Proxy icon + title-bar rename/move via double-click on title
        windowControllers.first?.window?.representedURL = fileURL
        tabStateManager?.updateBaseName(name)
        tabStateManager?.setState(content != lastSavedContent ? .modified : .saved)
    }
}
