import AppKit

/// Builds NSApp's main menu bar. `fileMenu`/`editMenu`/`viewMenu` are retained as
/// properties (not local variables) so the SAME NSMenu instances can later be
/// reused by in-window custom "File"/"Edit"/"View" buttons (MenuRowView) via
/// `menu.popUp(positioning:at:in:)`, without duplicating item construction.
public final class MenuBuilder {
    public let mainMenu = NSMenu()
    public let fileMenu = NSMenu(title: "File")
    public let editMenu = NSMenu(title: "Edit")
    public let viewMenu = NSMenu(title: "View")

    public init() {
        buildAppMenu()
        buildFileMenu()
        buildEditMenu()
        buildViewMenu()
        buildWindowMenu()
        buildHelpMenu()
    }

    private func buildAppMenu() {
        let appMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        appMenu.addItem(withTitle: "About JettyNotepad", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences...", action: #selector(AppDelegate.showPreferences(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit JettyNotepad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func buildFileMenu() {
        let fileMenuItem = NSMenuItem()
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        fileMenu.addItem(withTitle: "New", action: #selector(NSDocumentController.newDocument(_:)), keyEquivalent: "n")
        fileMenu.addItem(withTitle: "New Tab", action: #selector(AppDelegate.newTab(_:)), keyEquivalent: "t")
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

        // NOTE (Phase 0 — pure extraction, behavior unchanged): these remain the
        // original nil-target NSDocument selectors for now. Phase 3 retargets
        // Save/Save As/Revert/Print/Close to ShellWindowController explicitly
        // (see that phase's changes) once the shared-window architecture from
        // Phase 1 exists — nil-target resolution via NSWindowController.document
        // stops identifying "the active tab's document" unambiguously once
        // multiple documents share one window.
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
    }

    private func buildEditMenu() {
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
    }

    private func buildViewMenu() {
        let viewMenuItem = NSMenuItem()
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        let historyItem = NSMenuItem(title: "History", action: #selector(AppDelegate.showHistory(_:)), keyEquivalent: "H")
        historyItem.keyEquivalentModifierMask = [.command, .shift]
        viewMenu.addItem(historyItem)

        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Increase Font Size",
            action: #selector(EditorViewController.increaseFontSize(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Decrease Font Size",
            action: #selector(EditorViewController.decreaseFontSize(_:)), keyEquivalent: "-")
    }

    private func buildWindowMenu() {
        let windowMenu = NSMenu(title: "Window")
        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu
    }

    private func buildHelpMenu() {
        let helpMenu = NSMenu(title: "Help")
        let helpMenuItem = NSMenuItem()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)
        NSApp.helpMenu = helpMenu
    }
}
