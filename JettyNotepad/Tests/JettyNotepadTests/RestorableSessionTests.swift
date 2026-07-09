import Foundation
import JettyNotepadKit

// RestorableSession is deliberately a plain Codable struct, independent of
// NSCoder/AppKit's window-restoration machinery, specifically so this logic
// (the part most likely to have an off-by-one or ordering bug) is testable
// without the crash risk documented in SessionRestoreTests.swift.
func runRestorableSessionTests() {
    print("\nRestorableSessionTests:")

    test("saved tab kind round-trips through JSON") {
        let url = URL(fileURLWithPath: "/tmp/example.jnt")
        let session = RestorableSession(tabs: [.saved(url: url)], selectedIndex: 0)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(RestorableSession.self, from: data)
        try assertEqual(decoded, session)
    }

    test("draft tab kind round-trips through JSON") {
        let url = URL(fileURLWithPath: "/tmp/draft.jnt")
        let session = RestorableSession(tabs: [.draft(autosaveURL: url, cursor: 12, scroll: 34.5)], selectedIndex: 0)
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(RestorableSession.self, from: data)
        try assertEqual(decoded, session)
    }

    test("mixed saved and draft tabs preserve order") {
        let urlA = URL(fileURLWithPath: "/tmp/a.jnt")
        let urlB = URL(fileURLWithPath: "/tmp/b.jnt")
        let urlC = URL(fileURLWithPath: "/tmp/c.jnt")
        let session = RestorableSession(
            tabs: [.saved(url: urlA), .draft(autosaveURL: urlB, cursor: 1, scroll: 2), .saved(url: urlC)],
            selectedIndex: 1
        )
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(RestorableSession.self, from: data)
        try assertEqual(decoded, session)
        try assertEqual(decoded.tabs.count, 3)
    }

    test("clampedIndex clamps a stale/out-of-range index into range") {
        try assertEqual(RestorableSession.clampedIndex(5, tabCount: 3), 2)
        try assertEqual(RestorableSession.clampedIndex(-1, tabCount: 3), 0)
        try assertEqual(RestorableSession.clampedIndex(1, tabCount: 3), 1)
    }

    test("clampedIndex handles an empty tab list without going negative") {
        try assertEqual(RestorableSession.clampedIndex(0, tabCount: 0), 0)
        try assertEqual(RestorableSession.clampedIndex(5, tabCount: 0), 0)
    }
}
