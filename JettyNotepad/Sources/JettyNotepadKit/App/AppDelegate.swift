import AppKit
import UniformTypeIdentifiers

public class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        _ = JNTDocumentController()
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {}

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let mainMenu = NSMenu()
        NSApp.mainMenu = mainMenu

        // App menu
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        appMenu.addItem(withTitle: "About JettyNotepad", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit JettyNotepad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // File menu
        let fileMenu = NSMenu(title: "File")
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(newTab(_:)), keyEquivalent: "t")
        fileMenu.addItem(withTitle: "Open...", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")

        let recentMenu = NSMenu(title: "Open Recent")
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)
        recentMenu.addItem(.separator())
        recentMenu.addItem(withTitle: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: "")

        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")

        let saveAsItem = NSMenuItem(title: "Save As...", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAsItem)

        fileMenu.addItem(withTitle: "Revert to Saved",
            action: #selector(NSDocument.revertToSaved(_:)), keyEquivalent: "")

        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Print...", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")

        // Edit menu
        let editMenu = NSMenu(title: "Edit")
        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenu.addItem(.separator())
        let findItem = NSMenuItem(title: "Find...", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        findItem.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
        editMenu.addItem(findItem)

        // View menu
        let viewMenu = NSMenu(title: "View")
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let historyItem = NSMenuItem(title: "History", action: #selector(showHistory(_:)), keyEquivalent: "H")
        historyItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(historyItem)

        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Increase Font Size",
            action: #selector(EditorViewController.increaseFontSize(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Decrease Font Size",
            action: #selector(EditorViewController.decreaseFontSize(_:)), keyEquivalent: "-")

        // Window menu
        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        // Help menu
        let helpMenu = NSMenu(title: "Help")
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu
    }

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
