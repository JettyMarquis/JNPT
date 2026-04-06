import AppKit

public class JNTDocument: NSDocument {
    public var fileStore: JNTFileStore?
    public var content: String = ""
    public var lastSavedContent: String = ""
    public var fileUUID: UUID = UUID()
    public let autoSaveManager = AutoSaveManager()
    public var snapshotManager: SnapshotManager?
    public var sourceChainManager: SourceChainManager?
    private var tabStateManager: TabStateManager?
    private var isManualSave = false

    // External file support
    public var isExternalFile = false
    public var externalFileURL: URL?
    public var companionUUID: UUID?
    private var midTreeEditAcknowledged = false

    // MARK: - NSDocument Overrides

    public override class var autosavesInPlace: Bool { true }
    public override class var autosavesDrafts: Bool { true }

    public override class var readableTypes: [String] {
        ["com.jettymarquis.jettynotepad.jnt", "public.plain-text", "net.daringfireball.markdown"]
    }

    public override func writableTypes(for saveOperation: NSDocument.SaveOperationType) -> [String] {
        if isExternalFile {
            return ["public.plain-text", "net.daringfireball.markdown"]
        }
        return ["com.jettymarquis.jettynotepad.jnt"]
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
        let ext = url.pathExtension.lowercased()

        if ext == "jnt" {
            // Native .jnt file
            let store = try JNTFileStore(url: url)
            let state = try store.readDocumentState()
            self.fileStore = store
            self.snapshotManager = SnapshotManager(fileStore: store)
            self.sourceChainManager = SourceChainManager(fileStore: store)
            self.content = state.content
            self.lastSavedContent = state.content

            if let uuidStr = try store.readMetadata(key: "file_uuid"),
               let uuid = UUID(uuidString: uuidStr) {
                self.fileUUID = uuid
            }
        } else {
            // External file (.txt, .md)
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "JettyNotepad", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Unable to read file as text"])
            }
            self.content = text
            self.lastSavedContent = text
            self.isExternalFile = true
            self.externalFileURL = url

            // Open or create companion .jnt
            let (store, uuid, _) = try ExternalFileManager.openOrCreateCompanion(for: url, content: text)
            self.fileStore = store
            self.companionUUID = uuid
            self.fileUUID = uuid
            self.snapshotManager = SnapshotManager(fileStore: store)
            self.sourceChainManager = SourceChainManager(fileStore: store)
        }
    }

    // MARK: - Writing

    public override func write(to url: URL, ofType typeName: String) throws {
        if isExternalFile {
            try writeExternal(to: url)
            return
        }

        if fileStore == nil {
            // First save of a new document
            fileStore = try JNTFileStore.create(at: url, content: content, uuid: fileUUID)
            snapshotManager = SnapshotManager(fileStore: fileStore!)
            sourceChainManager = SourceChainManager(fileStore: fileStore!)
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

        // Update registry
        updateRegistry()
        lastSavedContent = content
        isManualSave = false
        updateTabState()
    }

    private func writeExternal(to url: URL) throws {
        // 1. Write original format
        let targetURL = externalFileURL ?? url
        try content.write(to: targetURL, atomically: true, encoding: .utf8)

        // 2. Update companion .jnt
        if let store = fileStore, content != lastSavedContent {
            let snapshotType = isManualSave ? "manualSave" : "autoSave"
            try snapshotManager?.createSnapshot(
                previousContent: lastSavedContent,
                currentContent: content,
                type: snapshotType,
                editSummary: nil
            )
            try store.saveContent(content, cursor: 0, scroll: 0)
            try snapshotManager?.evictIfNeeded()
        }

        updateRegistry()
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
                previousContent: lastSavedContent, currentContent: content,
                type: "forkPoint", editSummary: nil)
        } else {
            try snapshotManager?.createSnapshot(
                previousContent: content, currentContent: content,
                type: "forkPoint", editSummary: nil)
        }

        let parentSnapshots = try parentStore.readSnapshotManifest()
        let forkSeq = parentSnapshots.first?.seq ?? 0
        let childUUID = UUID()

        try parentStore.addChild(uuid: childUUID, path: url.path,
                                 forkTimestamp: Date(), forkSeq: forkSeq)
        try parentStore.saveContent(
            content,
            cursor: editorViewController?.textView.selectedRange().location ?? 0,
            scroll: Double(editorViewController?.textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0))

        let childStore = try JNTFileStore.create(at: url, content: content, uuid: childUUID)
        try childStore.writeMetadata(key: "parent_uuid", value: fileUUID.uuidString)
        try childStore.writeMetadata(key: "parent_path", value: parentStore.url.path)
        try childStore.writeMetadata(key: "parent_snapshot_seq", value: "\(forkSeq)")
        try childStore.writeMetadata(key: "parent_fork_timestamp",
                                     value: ISO8601DateFormatter().string(from: Date()))

        let emptyData = " ".data(using: .utf8)!
        let compressed = try (emptyData as NSData).compressed(using: .zlib) as Data
        _ = try childStore.insertSnapshot(type: "forkPoint", editSummary: nil,
                                          diffData: compressed,
                                          lengthBefore: content.utf8.count,
                                          lengthAfter: content.utf8.count)

        parentStore.close()
        self.fileStore = childStore
        self.snapshotManager = SnapshotManager(fileStore: childStore)
        self.sourceChainManager = SourceChainManager(fileStore: childStore)
        self.fileUUID = childUUID
        self.lastSavedContent = content
        updateRegistry()
        updateTabState()
    }

    // MARK: - Mid-Tree Edit Warning

    public func checkMidTreeEdit() {
        guard !midTreeEditAcknowledged,
              let chain = sourceChainManager,
              (try? chain.hasChildren()) == true else { return }

        let children = (try? chain.childrenInfo()) ?? []
        guard !children.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "This document has \(children.count) downstream version(s)"
        alert.informativeText = "Editing here may make those versions' history incomplete. We recommend saving as a new version."
        alert.addButton(withTitle: "Save As New Version")
        alert.addButton(withTitle: "Continue Editing")

        if let window = windowControllers.first?.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    self.runModalSavePanel(for: .saveAsOperation, delegate: nil,
                                           didSave: nil, contextInfo: nil)
                } else {
                    self.midTreeEditAcknowledged = true
                }
            }
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
        tabStateManager?.updateBaseName(name)

        if isExternalFile {
            tabStateManager?.setState(content != lastSavedContent ? .modified : .external)
        } else {
            tabStateManager?.setState(content != lastSavedContent ? .modified : .saved)
        }
    }

    private func updateRegistry() {
        guard let store = fileStore else { return }
        let entry = RegistryEntry(
            jntPath: store.url.path,
            isCompanion: isExternalFile,
            companionOriginalPath: externalFileURL?.path,
            displayName: JNTFileStore.displayNameFromContent(content),
            lastModifiedAt: ISO8601DateFormatter().string(from: Date()),
            parentUUID: try? store.readMetadata(key: "parent_uuid"),
            childUUIDs: ((try? store.readChildren()) ?? []).map { $0.childUUID.uuidString },
            sizeBytes: 0
        )
        try? RegistryManager.upsert(uuid: fileUUID, entry: entry)
    }
}
