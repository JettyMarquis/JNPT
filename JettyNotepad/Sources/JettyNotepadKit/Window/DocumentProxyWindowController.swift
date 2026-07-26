import AppKit

/// A window controller that owns NO real window. Registered via
/// `document.addWindowController(_:)` so `JNTDocument` still satisfies
/// NSDocument's "windowControllers non-empty" expectations (dirty-close
/// prompts, sheet attachment via `windowForSheet`, printing, etc.), without
/// each document creating its own real `NSWindow` — all tabs share the one
/// window owned by `ShellWindowController`.
public final class DocumentProxyWindowController: NSWindowController {
    public init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// NSDocumentController's standard flow calls `document.showWindows()` →
    /// each window controller's `showWindow(_:)` — e.g. when File > Open
    /// resolves to an ALREADY-open document (opening the same URL twice just
    /// fronts the existing document rather than reopening it). Front the
    /// shared window AND select this document's tab — otherwise the window
    /// comes forward still showing whatever tab was previously selected,
    /// leaving the user looking at the wrong document.
    public override func showWindow(_ sender: Any?) {
        guard let doc = document as? JNTDocument else { return }
        ShellWindowController.shared.selectTab(for: doc)
        ShellWindowController.shared.window?.makeKeyAndOrderFront(sender)
    }

    /// No-op: with no window of our own, and multiple documents sharing the
    /// real shell window, letting NSDocument's default implementation touch
    /// `window.title`/`representedURL` here would have every document fight
    /// over the same window's title. `ShellWindowController.refreshTab(for:)`
    /// is the only place that writes `window.title`, and only for the active tab.
    public override func synchronizeWindowTitleWithDocumentName() {}
}
