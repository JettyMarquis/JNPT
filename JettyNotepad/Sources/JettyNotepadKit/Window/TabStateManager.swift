import AppKit

public enum TabState {
    case saved
    case modified
    case external  // Phase 3

    public var symbol: String {
        switch self {
        case .saved:    return ""
        case .modified: return " \u{25CF}"  // ●
        case .external: return " \u{25CB}"  // ○
        }
    }
}

/// Pure formatter — computes the display label for a tab pill / window title
/// from a base name and state. No side effects, no window reference.
///
/// Previously this was a per-document class instance holding `weak var
/// window` and writing `window.title` directly as a side effect of every
/// state change. That design assumed one document = one window. Under the
/// shared-window architecture, only `ShellWindowController.refreshTab(for:)`
/// writes `window.title`, and only for the currently ACTIVE tab — a
/// per-document manager with its own window reference would let a
/// BACKGROUND tab's state change (e.g. its autosave finishing) clobber the
/// active tab's title.
public enum TabStateManager {
    public static func label(baseName: String, state: TabState) -> String {
        baseName + state.symbol
    }
}
