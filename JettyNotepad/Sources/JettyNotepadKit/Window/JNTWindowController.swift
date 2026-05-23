import AppKit

public class JNTWindowController: NSWindowController {
    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.tabbingMode = .preferred
        window.tabbingIdentifier = "com.jettymarquis.jettynotepad"
        window.setFrameAutosaveName("JettyNotepadMainWindow")
        window.title = "Untitled"
        window.minSize = NSSize(width: 400, height: 300)

        let editorVC = EditorViewController()
        window.contentViewController = editorVC

        self.init(window: window)
    }

    public override func windowDidLoad() {
        super.windowDidLoad()
    }
}

extension JNTWindowController: NSWindowDelegate {
    public func windowDidResignKey(_ notification: Notification) {
        if let doc = document as? JNTDocument {
            doc.autoSaveManager.documentDidLoseFocus()
        }
    }
}
