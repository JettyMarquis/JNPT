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

        // Save/Save As/Revert/Print/Close target ShellWindowController.shared
        // EXPLICITLY (not nil-target NSDocument selectors as before): under the
        // shared-window architecture (every document's own window controller is
        // a windowless DocumentProxyWindowController), nil-target resolution via
        // NSWindowController.document no longer identifies "the active tab's
        // document" unambiguously — it would also break entirely whenever a
        // different window (History, Preferences) is key. ShellWindowController
        // forwards to activeDocument and implements validateMenuItem to restore
        // the enabled/disabled logic NSDocument otherwise provides for free.
        let shell = ShellWindowController.shared
        let saveItem = NSMenuItem(title: "Save", action: #selector(ShellWindowController.saveActiveDocument(_:)), keyEquivalent: "s")
        saveItem.target = shell
        fileMenu.addItem(saveItem)

        let saveAsItem = NSMenuItem(title: "Save As...", action: #selector(ShellWindowController.saveActiveDocumentAs(_:)), keyEquivalent: "S")
        saveAsItem.keyEquivalentModifierMask = [.command, .shift]
        saveAsItem.target = shell
        fileMenu.addItem(saveAsItem)

        let revertItem = NSMenuItem(title: "Revert to Saved", action: #selector(ShellWindowController.revertActiveDocument(_:)), keyEquivalent: "")
        revertItem.target = shell
        fileMenu.addItem(revertItem)

        fileMenu.addItem(.separator())
        let closeItem = NSMenuItem(title: "Close", action: #selector(ShellWindowController.closeActiveTab(_:)), keyEquivalent: "w")
        closeItem.target = shell
        fileMenu.addItem(closeItem)
        fileMenu.addItem(.separator())
        let printItem = NSMenuItem(title: "Print...", action: #selector(ShellWindowController.printActiveDocument(_:)), keyEquivalent: "p")
        printItem.target = shell
        fileMenu.addItem(printItem)
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
