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

public class TabStateManager {
    private weak var window: NSWindow?
    private var baseName: String = "Untitled"
    private(set) public var state: TabState = .saved

    public init(window: NSWindow) {
        self.window = window
    }

    public func updateBaseName(_ name: String) {
        baseName = name
        applyTitle()
    }

    public func setState(_ newState: TabState) {
        state = newState
        applyTitle()
    }

    private func applyTitle() {
        window?.title = baseName + state.symbol
    }
}
