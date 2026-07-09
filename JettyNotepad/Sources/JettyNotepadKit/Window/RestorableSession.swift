import Foundation

/// Pure value-type representation of "which tabs were open, in what state" —
/// deliberately independent of NSCoder/NSKeyedArchiver so it can be unit
/// tested directly (round-trip encode/decode, index clamping) without going
/// through AppKit's window-restoration machinery. A prior session found that
/// testing NSDocument's restorable-state mechanism via a hand-built
/// NSKeyedArchiver/NSKeyedUnarchiver triggers a `requiresSecureCoding`
/// assertion that crashes the whole test process outside a real
/// window-restoration coder — this type is the part of that mechanism that
/// CAN be tested, by keeping it a plain Codable struct. `ShellWindowController`
/// only does a two-line "struct <-> Data <-> NSCoder" adapter around it.
public struct RestorableSession: Codable, Equatable {
    public enum TabKind: Codable, Equatable {
        /// Already saved to disk — reopen by URL. Cursor/scroll are NOT
        /// encoded here: `JNTDocument.read(from:)` already restores the
        /// file's own last-saved cursor/scroll, which is the authoritative,
        /// harder-to-go-stale source for a saved document.
        case saved(url: URL)

        /// Never saved (or saved but with edits not yet persisted) — recovered
        /// via NSDocument's own `autosavesDrafts` mechanism, which already
        /// persists a draft `.jnt` to the Autosave Information directory.
        /// Only the draft's URL is recorded here (not a duplicate copy of its
        /// full content), plus the cursor/scroll at encode time.
        case draft(autosaveURL: URL, cursor: Int, scroll: Double)
    }

    public var tabs: [TabKind]
    public var selectedIndex: Int

    public init(tabs: [TabKind], selectedIndex: Int) {
        self.tabs = tabs
        self.selectedIndex = selectedIndex
    }

    /// Defends against a corrupted/stale saved-state blob, or some encoded
    /// URLs failing to reopen (moved/deleted since last launch): never
    /// produces an out-of-range index.
    public static func clampedIndex(_ index: Int, tabCount: Int) -> Int {
        guard tabCount > 0 else { return 0 }
        return min(max(index, 0), tabCount - 1)
    }
}
