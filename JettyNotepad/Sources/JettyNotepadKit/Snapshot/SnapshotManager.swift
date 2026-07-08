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

    /// Untrusted .jnt files can carry a crafted zlib stream that expands enormously;
    /// bound decompression to a small multiple of the recorded pre-compression length
    /// so a malicious/corrupt blob can't exhaust memory.
    private static let decompressionSlack = 4
    private static let decompressionHardCap = 50 * 1024 * 1024 // 50MB

    /// Reconstruct content at a given snapshot sequence number.
    /// Walks backward from current content applying reverse diffs.
    /// `seq > targetSeq` (not `>=`): the selected snapshot's own reverse diff is
    /// excluded, so the result is the content AS SAVED AT that snapshot, not the
    /// content immediately before it.
    public func reconstructContent(at targetSeq: Int, currentContent: String) throws -> String {
        let manifest = try fileStore.readSnapshotManifest() // sorted desc by seq
        var result = currentContent

        for summary in manifest {
            guard summary.seq > targetSeq else { break }
            let compressed = try fileStore.readSnapshotDiff(seq: summary.seq)
            let expectedLength = max(summary.contentLengthBefore ?? 0, summary.contentLengthAfter ?? 0)
            let sizeCap = max(expectedLength * Self.decompressionSlack, 4096)
            let decompressed = try decompress(compressed, sizeCap: min(sizeCap, Self.decompressionHardCap),
                                              seq: summary.seq)
            guard let patchText = String(data: decompressed, encoding: .utf8) else {
                throw SnapshotError.corruptedDiff(summary.seq)
            }
            let patches = try dmp.patchFromText(patchText)
            let (applied, successFlags) = dmp.patchApply(patches: patches, text: result)
            guard successFlags.allSatisfy({ $0 }) else {
                throw SnapshotError.corruptedDiff(summary.seq)
            }
            result = applied
        }

        return result
    }

    private func decompress(_ compressed: Data, sizeCap: Int, seq: Int) throws -> Data {
        let decompressed = try (compressed as NSData).decompressed(using: .zlib) as Data
        guard decompressed.count <= sizeCap else {
            throw SnapshotError.corruptedDiff(seq)
        }
        return decompressed
    }

    // Eviction at the 100-snapshot cap is enforced solely by the `limit_snapshots`
    // SQLite trigger (FIFO by seq — see JNTSchema.swift). It does not distinguish
    // snapshot_type, so manualSave/forkPoint rows are NOT protected once a document
    // exceeds 100 snapshots: this is an accepted MVP limitation. Type-aware
    // protection requires merging an evicted snapshot's diff into its surviving
    // neighbor so the reverse-diff chain stays contiguous — skipping deletion by
    // type alone punches a hole in the chain and makes the "protected" snapshot
    // unreconstructable. That merge is deferred to Phase 2.5.
}

public enum SnapshotError: Error, LocalizedError {
    case corruptedDiff(Int)

    public var errorDescription: String? {
        switch self {
        case .corruptedDiff(let seq): return "Corrupted diff data at snapshot \(seq)"
        }
    }
}
