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
        autoSaveManager.start()
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
    }

    // MARK: - Reading

    public override func read(from url: URL, ofType typeName: String) throws {
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

    // MARK: - Writing

    public override func write(to url: URL, ofType typeName: String) throws {
        if fileStore == nil {
            // First save of a new document
            fileStore = try JNTFileStore.create(at: url, content: content, uuid: fileUUID)
            snapshotManager = SnapshotManager(fileStore: fileStore!)
        } else if fileStore!.url != url {
            // Save As — generation tracking
            try performSaveAs(to: url)
            return
        } else {
            // Regular save — create snapshot if content changed
            if content != lastSavedContent {
                let snapshotType = isManualSave ? "manualSave" : "autoSave"
                try snapshotManager?.createSnapshot(
                    previousContent: lastSavedContent,
                    currentContent: content,
                    type: snapshotType,
                    editSummary: nil
                )
                try snapshotManager?.evictIfNeeded()
            }

            try fileStore!.saveContent(
                content,
                cursor: editorViewController?.textView.selectedRange().location ?? 0,
                scroll: Double(editorViewController?.textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0)
            )
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

    // MARK: - Save As: Generation Tracking

    private func performSaveAs(to url: URL) throws {
        guard let parentStore = fileStore else { return }

        // 1. Create forkPoint snapshot in parent
        if content != lastSavedContent {
            try snapshotManager?.createSnapshot(
                previousContent: lastSavedContent,
                currentContent: content,
                type: "forkPoint",
                editSummary: nil
            )
        } else {
            // Even if content unchanged, mark the fork point
            try snapshotManager?.createSnapshot(
                previousContent: content,
                currentContent: content,
                type: "forkPoint",
                editSummary: nil
            )
        }

        // 2. Get parent's current snapshot seq for the fork reference
        let parentSnapshots = try parentStore.readSnapshotManifest()
        let forkSeq = parentSnapshots.first?.seq ?? 0

        // 3. Generate new UUID for the child
        let childUUID = UUID()

        // 4. Register child in parent's children table
        try parentStore.addChild(
            uuid: childUUID,
            path: url.path,
            forkTimestamp: Date(),
            forkSeq: forkSeq
        )

        // 5. Save parent state
        try parentStore.saveContent(
            content,
            cursor: editorViewController?.textView.selectedRange().location ?? 0,
            scroll: Double(editorViewController?.textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0)
        )

        // 6. Create new .jnt at target path
        let childStore = try JNTFileStore.create(at: url, content: content, uuid: childUUID)

        // 7. Write parent lineage metadata in child
        try childStore.writeMetadata(key: "parent_uuid", value: fileUUID.uuidString)
        try childStore.writeMetadata(key: "parent_path", value: parentStore.url.path)
        try childStore.writeMetadata(key: "parent_snapshot_seq", value: "\(forkSeq)")
        try childStore.writeMetadata(key: "parent_fork_timestamp",
                                     value: ISO8601DateFormatter().string(from: Date()))

        // 8. Create a forkPoint snapshot in child (empty diff, seq 0 equivalent)
        let dmp = DiffMatchPatch()
        let emptyPatch = dmp.patchToText(patches: [])
        let emptyData = (emptyPatch.isEmpty ? " " : emptyPatch).data(using: .utf8)!
        let compressed = try (emptyData as NSData).compressed(using: .zlib) as Data
        _ = try childStore.insertSnapshot(
            type: "forkPoint",
            editSummary: nil,
            diffData: compressed,
            lengthBefore: content.utf8.count,
            lengthAfter: content.utf8.count
        )

        // 9. Switch to child document
        parentStore.close()
        self.fileStore = childStore
        self.snapshotManager = SnapshotManager(fileStore: childStore)
        self.fileUUID = childUUID
        self.lastSavedContent = content
        updateTabState()
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
        tabStateManager?.updateBaseName(name)
        tabStateManager?.setState(content != lastSavedContent ? .modified : .saved)
    }
}
