import AppKit

/// Persistent root content view controller of the shared shell window.
/// Three stacked regions (the tab strip is NOT one of them — it's hosted as a
/// titlebar accessory view controller, see Phase 4 / ShellWindowController):
///   - menu row       (File/Edit/View buttons + gear — filled in Phase 3, empty placeholder until then)
///   - undo/redo row  (filled in Phase 3, empty placeholder until then)
///   - content container (the active tab's EditorViewController.view lives here)
///
/// `mount`/`unmount` use real `NSViewController` containment (`addChild`/
/// `removeFromParent`), not a bare `addSubview` — this is what puts
/// `EditorViewController` back in the responder chain so nil-target VC-level
/// actions (increaseFontSize/decreaseFontSize) keep working once the editor is
/// no longer the window's own contentViewController.
final class ShellContentViewController: NSViewController {
    private(set) var menuRowContainer: NSView!
    private(set) var undoRedoBarContainer: NSView!
    private(set) var contentContainer: NSView!

    private static let menuRowHeight: CGFloat = 32
    private static let undoRedoBarHeight: CGFloat = 28

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        menuRowContainer = NSView()
        undoRedoBarContainer = NSView()
        contentContainer = NSView()

        for v in [menuRowContainer, undoRedoBarContainer, contentContainer] {
            v?.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v!)
        }

        NSLayoutConstraint.activate([
            menuRowContainer.topAnchor.constraint(equalTo: root.topAnchor),
            menuRowContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            menuRowContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            menuRowContainer.heightAnchor.constraint(equalToConstant: Self.menuRowHeight),

            undoRedoBarContainer.topAnchor.constraint(equalTo: menuRowContainer.bottomAnchor),
            undoRedoBarContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            undoRedoBarContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            undoRedoBarContainer.heightAnchor.constraint(equalToConstant: Self.undoRedoBarHeight),

            contentContainer.topAnchor.constraint(equalTo: undoRedoBarContainer.bottomAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        self.view = root
    }

    /// Puts `editor` in the responder chain (via `addChild`) and its view into
    /// `contentContainer`, pinned to all four edges.
    func mount(_ editor: EditorViewController) {
        addChild(editor)
        editor.view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(editor.view)
        NSLayoutConstraint.activate([
            editor.view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            editor.view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            editor.view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            editor.view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])
    }

    /// Reverses `mount(_:)` — removes the view AND the containment relationship,
    /// so a backgrounded editor is not left in the responder chain receiving
    /// actions meant for the active tab.
    func unmount(_ editor: EditorViewController) {
        editor.view.removeFromSuperview()
        editor.removeFromParent()
    }
}
