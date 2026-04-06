import Foundation

/// Clean-room diff-match-patch implementation.
/// Character-level diffs using Myers' O(ND) difference algorithm.
public class DiffMatchPatch {
    /// Cost of an empty edit in cleanup passes.
    public var diffEditCost: Int = 4
    /// Margin around patch context.
    public var patchMargin: Int = 4

    public init() {}

    // MARK: - Diff: Main Entry

    /// Compute character-level diffs between two strings.
    public func diffMain(text1: String, text2: String) -> [Diff] {
        if text1 == text2 {
            if text1.isEmpty { return [] }
            return [Diff(.equal, text1)]
        }
        if text1.isEmpty { return [Diff(.insert, text2)] }
        if text2.isEmpty { return [Diff(.delete, text1)] }

        // Check for common prefix/suffix
        let chars1 = Array(text1.unicodeScalars)
        let chars2 = Array(text2.unicodeScalars)

        let commonPrefixLen = commonPrefix(text1, text2)
        // Clamp suffix so it doesn't overlap with prefix
        let maxSuffix = min(chars1.count, chars2.count) - commonPrefixLen
        let commonSuffixLen = min(commonSuffix(text1, text2), max(0, maxSuffix))

        let prefixText = String(String.UnicodeScalarView(chars1[..<commonPrefixLen]))
        let suffixStart1 = chars1.count - commonSuffixLen
        let suffixStart2 = chars2.count - commonSuffixLen
        let suffixText = String(String.UnicodeScalarView(chars1[suffixStart1...]))

        let mid1 = Array(chars1[commonPrefixLen..<suffixStart1])
        let mid2 = Array(chars2[commonPrefixLen..<suffixStart2])

        var diffs = diffCompute(mid1, mid2)

        // Add back prefix/suffix
        if !prefixText.isEmpty {
            diffs.insert(Diff(.equal, prefixText), at: 0)
        }
        if !suffixText.isEmpty {
            diffs.append(Diff(.equal, suffixText))
        }

        diffCleanupMerge(&diffs)
        return diffs
    }

    // MARK: - Diff: Core Algorithm

    private func diffCompute(_ chars1: [Unicode.Scalar], _ chars2: [Unicode.Scalar]) -> [Diff] {
        let text1 = String(String.UnicodeScalarView(chars1))
        let text2 = String(String.UnicodeScalarView(chars2))

        if chars1.isEmpty { return [Diff(.insert, text2)] }
        if chars2.isEmpty { return [Diff(.delete, text1)] }

        // Check if shorter text is a substring of the longer
        let longText = chars1.count > chars2.count ? text1 : text2
        let shortText = chars1.count > chars2.count ? text2 : text1
        if let idx = longText.range(of: shortText) {
            let op: Diff.Operation = chars1.count > chars2.count ? .delete : .insert
            let before = String(longText[longText.startIndex..<idx.lowerBound])
            let after = String(longText[idx.upperBound...])
            var result: [Diff] = []
            if !before.isEmpty { result.append(Diff(op, before)) }
            result.append(Diff(.equal, shortText))
            if !after.isEmpty { result.append(Diff(op, after)) }
            return result
        }

        // Use Myers' bisect algorithm
        return diffBisect(chars1, chars2)
    }

    /// Myers' O(ND) bisect diff algorithm.
    private func diffBisect(_ chars1: [Unicode.Scalar], _ chars2: [Unicode.Scalar]) -> [Diff] {
        let n = chars1.count
        let m = chars2.count
        let maxD = (n + m + 1) / 2
        let vOffset = maxD
        let vLength = 2 * maxD + 2

        var v1 = Array(repeating: -1, count: vLength)
        var v2 = Array(repeating: -1, count: vLength)
        v1[vOffset + 1] = 0
        v2[vOffset + 1] = 0

        let delta = n - m

        for d in 0...maxD {
            // Forward pass
            for k in stride(from: -d, through: d, by: 2) {
                let kIdx = k + vOffset
                var x: Int
                if k == -d || (k != d && v1[kIdx - 1] < v1[kIdx + 1]) {
                    x = v1[kIdx + 1]
                } else {
                    x = v1[kIdx - 1] + 1
                }
                var y = x - k
                while x < n && y < m && chars1[x] == chars2[y] {
                    x += 1
                    y += 1
                }
                v1[kIdx] = x
                if delta % 2 != 0 {
                    let k2 = vOffset + delta - k
                    if k2 >= 0 && k2 < vLength && v2[k2] != -1 {
                        if x >= n - v2[k2] {
                            return diffBisectSplit(chars1, chars2, x, y)
                        }
                    }
                }
            }

            // Reverse pass
            for k in stride(from: -d, through: d, by: 2) {
                let kIdx = k + vOffset
                var x: Int
                if k == -d || (k != d && v2[kIdx - 1] < v2[kIdx + 1]) {
                    x = v2[kIdx + 1]
                } else {
                    x = v2[kIdx - 1] + 1
                }
                var y = x - k
                while x < n && y < m && chars1[n - x - 1] == chars2[m - y - 1] {
                    x += 1
                    y += 1
                }
                v2[kIdx] = x
                if delta % 2 == 0 {
                    let k2 = vOffset + delta - k
                    if k2 >= 0 && k2 < vLength && v1[k2] != -1 {
                        if n - v1[k2] <= x {  // Mirror check
                            return diffBisectSplit(chars1, chars2, v1[k2], v1[k2] - (k2 - vOffset))
                        }
                    }
                }
            }
        }

        // Fallback: no commonality found
        let text1 = String(String.UnicodeScalarView(chars1))
        let text2 = String(String.UnicodeScalarView(chars2))
        return [Diff(.delete, text1), Diff(.insert, text2)]
    }

    private func diffBisectSplit(_ chars1: [Unicode.Scalar], _ chars2: [Unicode.Scalar],
                                 _ x: Int, _ y: Int) -> [Diff] {
        let chars1a = Array(chars1[..<x])
        let chars2a = Array(chars2[..<y])
        let chars1b = Array(chars1[x...])
        let chars2b = Array(chars2[y...])

        let text1a = String(String.UnicodeScalarView(chars1a))
        let text2a = String(String.UnicodeScalarView(chars2a))
        let text1b = String(String.UnicodeScalarView(chars1b))
        let text2b = String(String.UnicodeScalarView(chars2b))

        var diffs = diffMain(text1: text1a, text2: text2a)
        diffs.append(contentsOf: diffMain(text1: text1b, text2: text2b))
        return diffs
    }

    // MARK: - Diff Cleanup: Semantic

    /// Reduce diffs to human-meaningful boundaries.
    public func diffCleanupSemantic(_ diffs: inout [Diff]) {
        guard diffs.count > 1 else { return }

        var changes = true
        while changes {
            changes = false
            var i = 1
            while i < diffs.count - 1 {
                if diffs[i].operation == .equal && diffs[i].text.count < diffEditCost {
                    // Small equality — check if merging neighbors is cleaner
                    if i > 0 && i < diffs.count - 1
                        && diffs[i - 1].operation != .equal
                        && diffs[i + 1].operation != .equal
                        && diffs[i - 1].operation != diffs[i + 1].operation {
                        // Absorb equality into neighbors
                        diffs[i - 1].text += diffs[i].text
                        diffs[i + 1].text = diffs[i].text + diffs[i + 1].text
                        diffs.remove(at: i)
                        changes = true
                        continue
                    }
                }
                i += 1
            }
        }
        diffCleanupMerge(&diffs)
    }

    // MARK: - Diff Cleanup: Merge

    /// Reorder and merge adjacent edits.
    public func diffCleanupMerge(_ diffs: inout [Diff]) {
        guard !diffs.isEmpty else { return }
        diffs.append(Diff(.equal, ""))  // Sentinel

        var i = 0
        var countDelete = 0
        var countInsert = 0
        var textDelete = ""
        var textInsert = ""

        while i < diffs.count {
            switch diffs[i].operation {
            case .insert:
                countInsert += 1
                textInsert += diffs[i].text
                i += 1
            case .delete:
                countDelete += 1
                textDelete += diffs[i].text
                i += 1
            case .equal:
                if countDelete + countInsert > 1 {
                    // Merge previous edits
                    let start = i - countDelete - countInsert
                    diffs.removeSubrange(start..<i)
                    i = start
                    if !textDelete.isEmpty {
                        diffs.insert(Diff(.delete, textDelete), at: i)
                        i += 1
                    }
                    if !textInsert.isEmpty {
                        diffs.insert(Diff(.insert, textInsert), at: i)
                        i += 1
                    }
                } else if countDelete == 0 && countInsert == 0 {
                    // Merge adjacent equals
                    if i > 0 && diffs[i - 1].operation == .equal {
                        diffs[i - 1].text += diffs[i].text
                        diffs.remove(at: i)
                        continue
                    }
                }
                countInsert = 0
                countDelete = 0
                textDelete = ""
                textInsert = ""
                i += 1
            }
        }

        // Remove sentinel if empty
        if let last = diffs.last, last.text.isEmpty {
            diffs.removeLast()
        }

        // Merge adjacent equal entries that might have been created
        var j = 0
        while j < diffs.count - 1 {
            if diffs[j].operation == .equal && diffs[j + 1].operation == .equal {
                diffs[j].text += diffs[j + 1].text
                diffs.remove(at: j + 1)
            } else {
                j += 1
            }
        }
    }

    // MARK: - Patch: Make

    /// Create patches from two strings.
    public func patchMake(text1: String, text2: String) -> [Patch] {
        let diffs = diffMain(text1: text1, text2: text2)
        return patchMake(text1: text1, diffs: diffs)
    }

    /// Create patches from text1 and precomputed diffs.
    /// Produces a single patch containing all diffs — simple, correct for snapshot use.
    public func patchMake(text1: String, diffs: [Diff]) -> [Patch] {
        guard !diffs.isEmpty else { return [] }
        if diffs.allSatisfy({ $0.operation == .equal }) { return [] }

        var patch = Patch()
        patch.start1 = 0
        patch.start2 = 0

        for diff in diffs {
            patch.diffs.append(diff)
            switch diff.operation {
            case .equal:
                patch.length1 += diff.text.count
                patch.length2 += diff.text.count
            case .delete:
                patch.length1 += diff.text.count
            case .insert:
                patch.length2 += diff.text.count
            }
        }

        return [patch]
    }

    // MARK: - Patch: Apply

    /// Apply patches to text. Returns (result, successFlags).
    /// Uses segment replacement: build old/new text from diffs, replace old with new at position.
    public func patchApply(patches: [Patch], text: String) -> (String, [Bool]) {
        guard !patches.isEmpty else { return (text, []) }

        var result = text
        var results = [Bool](repeating: false, count: patches.count)
        var delta = 0

        for (idx, patch) in patches.enumerated() {
            // Build the "old" (text1 segment) and "new" (text2 segment) from diffs
            var oldText = ""
            var newText = ""
            for diff in patch.diffs {
                switch diff.operation {
                case .equal:
                    oldText += diff.text
                    newText += diff.text
                case .delete:
                    oldText += diff.text
                case .insert:
                    newText += diff.text
                }
            }

            let expectedStart = patch.start2 + delta
            let safeStart = min(max(expectedStart, 0), result.count)
            let safeEnd = min(safeStart + oldText.count, result.count)

            let startIdx = result.index(result.startIndex, offsetBy: safeStart)
            let endIdx = result.index(result.startIndex, offsetBy: safeEnd)
            let found = String(result[startIdx..<endIdx])

            results[idx] = (found == oldText)
            result.replaceSubrange(startIdx..<endIdx, with: newText)
            delta += newText.count - oldText.count
        }

        return (result, results)
    }

    // MARK: - Patch: Serialize / Deserialize

    /// Serialize patches to the standard text format.
    public func patchToText(patches: [Patch]) -> String {
        patches.map { $0.description }.joined()
    }

    /// Parse patches from the standard text format.
    public func patchFromText(_ text: String) throws -> [Patch] {
        guard !text.isEmpty else { return [] }

        var patches: [Patch] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var i = 0

        while i < lines.count {
            let line = lines[i]
            guard line.hasPrefix("@@") else {
                i += 1
                continue
            }

            // Parse header: @@ -start,len +start,len @@
            var patch = try parseHeader(line)
            i += 1

            while i < lines.count && !lines[i].hasPrefix("@@") {
                let diffLine = lines[i]
                guard !diffLine.isEmpty else { i += 1; continue }

                let op: Diff.Operation
                switch diffLine.first {
                case "+": op = .insert
                case "-": op = .delete
                case " ": op = .equal
                default:
                    i += 1
                    continue
                }

                let content = String(diffLine.dropFirst()).decodingFromPatch()
                patch.diffs.append(Diff(op, content))
                i += 1
            }

            patches.append(patch)
        }

        return patches
    }

    private func parseHeader(_ line: String) throws -> Patch {
        // @@ -start1,len1 +start2,len2 @@
        let pattern = #"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            throw DiffMatchPatchError.invalidPatchHeader(line)
        }

        var patch = Patch()

        func capture(_ idx: Int) -> Int? {
            let range = match.range(at: idx)
            guard range.location != NSNotFound, let r = Range(range, in: line) else { return nil }
            return Int(line[r])
        }

        let s1 = capture(1) ?? 0
        let l1 = capture(2)
        let s2 = capture(3) ?? 0
        let l2 = capture(4)

        if let l1 = l1 {
            patch.start1 = s1 == 0 ? 0 : s1 - 1
            patch.length1 = l1
        } else {
            patch.start1 = s1 == 0 ? 0 : s1 - 1
            patch.length1 = 1
        }

        if let l2 = l2 {
            patch.start2 = s2 == 0 ? 0 : s2 - 1
            patch.length2 = l2
        } else {
            patch.start2 = s2 == 0 ? 0 : s2 - 1
            patch.length2 = 1
        }

        return patch
    }

    // MARK: - Common Prefix / Suffix

    func commonPrefix(_ text1: String, _ text2: String) -> Int {
        let s1 = Array(text1.unicodeScalars)
        let s2 = Array(text2.unicodeScalars)
        let n = min(s1.count, s2.count)
        for i in 0..<n {
            if s1[i] != s2[i] { return i }
        }
        return n
    }

    func commonSuffix(_ text1: String, _ text2: String) -> Int {
        let s1 = Array(text1.unicodeScalars)
        let s2 = Array(text2.unicodeScalars)
        let n = min(s1.count, s2.count)
        for i in 0..<n {
            if s1[s1.count - 1 - i] != s2[s2.count - 1 - i] { return i }
        }
        return n
    }
}

public enum DiffMatchPatchError: Error, LocalizedError {
    case invalidPatchHeader(String)
    case invalidPatchContent(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPatchHeader(let h): return "Invalid patch header: \(h)"
        case .invalidPatchContent(let c): return "Invalid patch content: \(c)"
        }
    }
}
