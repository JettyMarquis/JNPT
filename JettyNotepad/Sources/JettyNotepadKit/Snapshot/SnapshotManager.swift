import Foundation

public class SnapshotManager {
    public let fileStore: JNTFileStore
    public let dmp = DiffMatchPatch()

    public init(fileStore: JNTFileStore) {
        self.fileStore = fileStore
    }

    /// Create a reverse-diff snapshot: applying the diff to currentContent yields previousContent.
    @discardableResult
    public func createSnapshot(previousContent: String, currentContent: String,
                               type: String, editSummary: String?) throws -> Int64 {
        // Reverse patches: transform currentContent → previousContent
        let patches = dmp.patchMake(text1: currentContent, text2: previousContent)
        let patchText = dmp.patchToText(patches: patches)
        let patchData = patchText.data(using: .utf8)!
        let compressed = try (patchData as NSData).compressed(using: .zlib) as Data

        return try fileStore.insertSnapshot(
            type: type,
            editSummary: editSummary,
            diffData: compressed,
            lengthBefore: previousContent.utf8.count,
            lengthAfter: currentContent.utf8.count
        )
    }

    /// Reconstruct content at a given snapshot sequence number.
    /// Walks backward from current content applying reverse diffs.
    public func reconstructContent(at targetSeq: Int, currentContent: String) throws -> String {
        let manifest = try fileStore.readSnapshotManifest() // sorted desc by seq
        var result = currentContent

        for summary in manifest {
            guard summary.seq >= targetSeq else { break }
            let compressed = try fileStore.readSnapshotDiff(seq: summary.seq)
            let decompressed = try (compressed as NSData).decompressed(using: .zlib) as Data
            guard let patchText = String(data: decompressed, encoding: .utf8) else {
                throw SnapshotError.corruptedDiff(summary.seq)
            }
            let patches = try dmp.patchFromText(patchText)
            let (applied, _) = dmp.patchApply(patches: patches, text: result)
            result = applied
        }

        return result
    }

    /// Smart eviction when snapshot count exceeds 100.
    /// Priority: merge adjacent autoSaves within 2min, thin >7d autoSaves, thin >30d.
    /// Never evict: manualSave, forkPoint.
    public func evictIfNeeded() throws {
        let count = try fileStore.snapshotCount()
        guard count > 100 else { return }

        let manifest = try fileStore.readSnapshotManifest()
        let now = Date()

        // Find autoSave snapshots eligible for eviction
        var toEvict: [Int] = []

        // Pass 1: merge adjacent autoSaves within 2 minutes of each other
        let autoSaves = manifest.filter { $0.snapshotType == "autoSave" }
        for i in 0..<(autoSaves.count - 1) {
            let current = autoSaves[i]
            let next = autoSaves[i + 1]
            if abs(current.timestamp.timeIntervalSince(next.timestamp)) < 120 {
                toEvict.append(next.seq) // Keep the newer one, evict older
            }
            if count - toEvict.count <= 100 { break }
        }

        // Pass 2: thin autoSaves older than 7 days (keep every other one)
        if count - toEvict.count > 100 {
            let oldAutoSaves = autoSaves.filter {
                now.timeIntervalSince($0.timestamp) > 7 * 86400
                && !toEvict.contains($0.seq)
            }
            for (i, snap) in oldAutoSaves.enumerated() {
                if i % 2 == 1 { toEvict.append(snap.seq) }
                if count - toEvict.count <= 100 { break }
            }
        }

        // Pass 3: thin autoSaves older than 30 days more aggressively (keep every 3rd)
        if count - toEvict.count > 100 {
            let veryOldAutoSaves = autoSaves.filter {
                now.timeIntervalSince($0.timestamp) > 30 * 86400
                && !toEvict.contains($0.seq)
            }
            for (i, snap) in veryOldAutoSaves.enumerated() {
                if i % 3 != 0 { toEvict.append(snap.seq) }
                if count - toEvict.count <= 100 { break }
            }
        }

        // Delete evicted snapshots
        for seq in toEvict {
            try fileStore.db.executeWithParams(
                "DELETE FROM snapshots WHERE seq = ?1;",
                params: [.int(Int64(seq))]
            )
        }
    }
}

public enum SnapshotError: Error, LocalizedError {
    case corruptedDiff(Int)

    public var errorDescription: String? {
        switch self {
        case .corruptedDiff(let seq): return "Corrupted diff data at snapshot \(seq)"
        }
    }
}
