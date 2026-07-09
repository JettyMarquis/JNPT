import AppKit
import UniformTypeIdentifiers

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBuilder: MenuBuilder?

    public override init() {
        _ = JNTDocumentController()
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        let builder = MenuBuilder()
        menuBuilder = builder
        NSApp.mainMenu = builder.mainMenu
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched via `swift run` (no app bundle/Info.plist), the process
        // never automatically becomes the frontmost app — the window can be
        // visible while keyboard input still goes to the launching terminal.
        // A real .app launched from Finder does not need this.
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Actions

    @objc func newTab(_ sender: Any?) {
        guard let keyWindow = NSApp.keyWindow else {
            NSDocumentController.shared.newDocument(sender)
            return
        }
        do {
            let doc = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
            doc.makeWindowControllers()
            if let newWindow = doc.windowControllers.first?.window {
                keyWindow.addTabbedWindow(newWindow, ordered: .above)
                newWindow.makeKeyAndOrderFront(nil)
            }
        } catch {
            NSDocumentController.shared.newDocument(sender)
        }
    }

    private var historyPanel: HistoryPanelController?

    @objc func showHistory(_ sender: Any?) {
        guard let doc = NSDocumentController.shared.currentDocument as? JNTDocument else { return }
        guard doc.fileStore != nil else {
            let alert = NSAlert()
            alert.messageText = "No History Available"
            alert.informativeText = "Save the document first to start tracking history."
            alert.runModal()
            return
        }
        historyPanel = HistoryPanelController(document: doc)
        historyPanel?.showWindow(sender)
    }

    private var preferencesWC: PreferencesWindowController?

    @objc func showPreferences(_ sender: Any?) {
        if preferencesWC == nil {
            preferencesWC = PreferencesWindowController()
        }
        preferencesWC?.showWindow(sender)
    }
}
