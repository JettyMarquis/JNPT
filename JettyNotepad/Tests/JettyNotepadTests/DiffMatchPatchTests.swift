import Foundation
import JettyNotepadKit

func runDiffMatchPatchTests() {
    let dmp = DiffMatchPatch()

    print("\nDiffMatchPatchTests:")

    // --- Diff Tests ---

    test("diff: empty strings") {
        let diffs = dmp.diffMain(text1: "", text2: "")
        try assertEqual(diffs.count, 0)
    }

    test("diff: identical strings") {
        let diffs = dmp.diffMain(text1: "abc", text2: "abc")
        try assertEqual(diffs.count, 1)
        try assertEqual(diffs[0].operation, .equal)
        try assertEqual(diffs[0].text, "abc")
    }

    test("diff: completely different") {
        let diffs = dmp.diffMain(text1: "abc", text2: "xyz")
        // Should produce delete + insert (order may vary but both must be present)
        let hasDelete = diffs.contains(where: { $0.operation == .delete })
        let hasInsert = diffs.contains(where: { $0.operation == .insert })
        try assertTrue(hasDelete, "missing delete")
        try assertTrue(hasInsert, "missing insert")
    }

    test("diff: single character change") {
        let diffs = dmp.diffMain(text1: "abc", text2: "axc")
        // Should have equal(a), delete(b)/insert(x), equal(c)
        let reconstructed = applyDiffsForward(text1: "abc", diffs: diffs)
        try assertEqual(reconstructed, "axc")
    }

    test("diff: word insertion") {
        let diffs = dmp.diffMain(text1: "hello world", text2: "hello beautiful world")
        let reconstructed = applyDiffsForward(text1: "hello world", diffs: diffs)
        try assertEqual(reconstructed, "hello beautiful world")
    }

    test("diff: paragraph deletion") {
        let text1 = "First paragraph.\nSecond paragraph.\nThird paragraph."
        let text2 = "First paragraph.\nThird paragraph."
        let diffs = dmp.diffMain(text1: text1, text2: text2)
        let reconstructed = applyDiffsForward(text1: text1, diffs: diffs)
        try assertEqual(reconstructed, text2)
    }

    test("diff: Unicode Chinese text") {
        let text1 = "你好世界"
        let text2 = "你好美丽世界"
        let diffs = dmp.diffMain(text1: text1, text2: text2)
        let reconstructed = applyDiffsForward(text1: text1, diffs: diffs)
        try assertEqual(reconstructed, text2)
    }

    test("diff: emoji") {
        let text1 = "Hello 🌍"
        let text2 = "Hello 🌎🌍"
        let diffs = dmp.diffMain(text1: text1, text2: text2)
        let reconstructed = applyDiffsForward(text1: text1, diffs: diffs)
        try assertEqual(reconstructed, text2)
    }

    // --- Patch Tests ---

    test("patch: round-trip simple") {
        let text1 = "The quick brown fox jumps."
        let text2 = "The quick red fox leaps."
        let patches = dmp.patchMake(text1: text1, text2: text2)
        let (result, _) = dmp.patchApply(patches: patches, text: text1)
        try assertEqual(result, text2)
    }

    test("patch: round-trip empty to text") {
        let text1 = ""
        let text2 = "Hello, World!"
        let patches = dmp.patchMake(text1: text1, text2: text2)
        let (result, _) = dmp.patchApply(patches: patches, text: text1)
        try assertEqual(result, text2)
    }

    test("patch: round-trip text to empty") {
        let text1 = "Hello, World!"
        let text2 = ""
        let patches = dmp.patchMake(text1: text1, text2: text2)
        let (result, _) = dmp.patchApply(patches: patches, text: text1)
        try assertEqual(result, text2)
    }

    test("patch: serialization round-trip") {
        let text1 = "First version of the document."
        let text2 = "Second version of the document with changes."
        let patches = dmp.patchMake(text1: text1, text2: text2)
        let serialized = dmp.patchToText(patches: patches)
        let deserialized = try dmp.patchFromText(serialized)

        // Apply deserialized patches — must produce same result
        let (result, _) = dmp.patchApply(patches: deserialized, text: text1)
        try assertEqual(result, text2)
    }

    test("patch: reverse diff (snapshot style)") {
        let previous = "Version A content"
        let current = "Version B content with additions"
        // Create reverse patches: current → previous
        let reversePatches = dmp.patchMake(text1: current, text2: previous)
        let (restored, _) = dmp.patchApply(patches: reversePatches, text: current)
        try assertEqual(restored, previous)
    }

    test("patch: Unicode round-trip") {
        let text1 = "日本語テスト"
        let text2 = "日本語の新しいテスト"
        let patches = dmp.patchMake(text1: text1, text2: text2)
        let serialized = dmp.patchToText(patches: patches)
        let deserialized = try dmp.patchFromText(serialized)
        let (result, _) = dmp.patchApply(patches: deserialized, text: text1)
        try assertEqual(result, text2)
    }

    test("patch: no change produces empty patches") {
        let patches = dmp.patchMake(text1: "same", text2: "same")
        try assertEqual(patches.count, 0)
    }

    // --- Performance ---

    test("diff: 50KB text in reasonable time") {
        let base = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 1200)
        var modified = base
        // Insert text at 3 positions
        let insertPositions = [base.count / 4, base.count / 2, (base.count * 3) / 4]
        for pos in insertPositions.reversed() {
            let idx = modified.index(modified.startIndex, offsetBy: min(pos, modified.count))
            modified.insert(contentsOf: " [INSERTED MARKER] ", at: idx)
        }

        let start = CFAbsoluteTimeGetCurrent()
        let diffs = dmp.diffMain(text1: base, text2: modified)
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        try assertTrue(elapsed < 5.0, "diff took \(elapsed)s, expected < 5s")
        // Verify correctness
        let reconstructed = applyDiffsForward(text1: base, diffs: diffs)
        try assertEqual(reconstructed, modified)
    }
}

// Helper: reconstruct text2 from text1 by applying diffs forward
private func applyDiffsForward(text1: String, diffs: [Diff]) -> String {
    var result = ""
    for diff in diffs {
        switch diff.operation {
        case .equal:  result += diff.text
        case .insert: result += diff.text
        case .delete: break // skip deleted text
        }
    }
    return result
}
