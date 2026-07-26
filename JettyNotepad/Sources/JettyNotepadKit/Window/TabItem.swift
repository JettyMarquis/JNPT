import AppKit

/// One open document, tracked as a tab in the shared `ShellWindowController`
/// window. Each tab owns its own `JNTDocument` (with its own fileStore/
/// snapshotManager/autoSaveManager — only the WINDOW is shared) and its own
/// `EditorViewController`.
public final class TabItem {
    public let document: JNTDocument
    public let editor: EditorViewController
    let proxy: DocumentProxyWindowController
    public var displayName: String
    public var isModified: Bool

    /// Guards against a second close request landing while an earlier one's
    /// async `canClose` save-sheet is still in flight (e.g. double-clicking the
    /// tab's close button, or ⌘W while the sheet is already showing).
    var isClosing = false

    init(document: JNTDocument, editor: EditorViewController, proxy: DocumentProxyWindowController,
         displayName: String, isModified: Bool) {
        self.document = document
        self.editor = editor
        self.proxy = proxy
        self.displayName = displayName
        self.isModified = isModified
    }
}
