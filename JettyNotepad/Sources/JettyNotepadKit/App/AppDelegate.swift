import AppKit

public class AppDelegate: NSObject, NSApplicationDelegate {
    public override init() {
        // Instantiate our custom document controller before NSDocumentController.shared is accessed
        _ = JNTDocumentController()
        super.init()
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        setupMenuBar()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // NSDocumentController handles opening untitled document or restoring session
    }

    public func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

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
        fileMenu.addItem(withTitle: "Open...", action: #selector(NSDocumentController.openDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Save", action: #selector(NSDocument.save(_:)), keyEquivalent: "s")

        let saveAsItem = NSMenuItem(title: "Save As...", action: #selector(NSDocument.saveAs(_:)), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(saveAsItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenu.addItem(.separator())

        let printItem = NSMenuItem(title: "Print...", action: #selector(NSDocument.printDocument(_:)), keyEquivalent: "p")
        fileMenu.addItem(printItem)

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

        // Format menu
        let formatMenu = NSMenu(title: "Format")
        let formatMenuItem = NSMenuItem()
        formatMenuItem.submenu = formatMenu
        mainMenu.addItem(formatMenuItem)

        let mdToggle = NSMenuItem(title: "Markdown Rendering",
                                   action: #selector(toggleMarkdown(_:)), keyEquivalent: "M")
        mdToggle.keyEquivalentModifierMask = [.command, .shift]
        formatMenu.addItem(mdToggle)

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

    @objc func toggleMarkdown(_ sender: NSMenuItem) {
        guard let doc = NSDocumentController.shared.currentDocument as? JNTDocument,
              let editor = doc.editorViewController else { return }
        let newState = !(editor.jntTextStorage?.markdownRenderingEnabled ?? false)
        editor.toggleMarkdownRendering(newState)
        sender.state = newState ? .on : .off
    }

    @objc func showPreferences(_ sender: Any?) {
        if preferencesWC == nil {
            preferencesWC = PreferencesWindowController()
        }
        preferencesWC?.showWindow(sender)
    }
}
