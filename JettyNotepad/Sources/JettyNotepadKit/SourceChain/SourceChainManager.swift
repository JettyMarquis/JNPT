import Foundation

public struct ParentInfo {
    public let uuid: UUID
    public let path: String?
    public let snapshotSeq: Int?
    public let forkTimestamp: Date?
}

public struct ChildInfo {
    public let uuid: UUID
    public let path: String?
    public let forkTimestamp: Date
    public let forkSnapshotSeq: Int?
}

public enum ParentResolution {
    case found(URL)
    case moved(URL)          // File found at a different path via registry
    case unreachable(UUID)   // UUID known but file not found
    case noParent
}

public class SourceChainManager {
    public let fileStore: JNTFileStore

    public init(fileStore: JNTFileStore) {
        self.fileStore = fileStore
    }

    /// Read parent info from metadata.
    public func parentInfo() throws -> ParentInfo? {
        guard let uuidStr = try fileStore.readMetadata(key: "parent_uuid"),
              let uuid = UUID(uuidString: uuidStr) else { return nil }

        let path = try fileStore.readMetadata(key: "parent_path")
        let seqStr = try fileStore.readMetadata(key: "parent_snapshot_seq")
        let seq = seqStr.flatMap { Int($0) }
        let tsStr = try fileStore.readMetadata(key: "parent_fork_timestamp")
        let ts = tsStr.flatMap { ISO8601DateFormatter().date(from: $0) }

        return ParentInfo(uuid: uuid, path: path, snapshotSeq: seq, forkTimestamp: ts)
    }

    /// Read children from the children table.
    public func childrenInfo() throws -> [ChildInfo] {
        let records = try fileStore.readChildren()
        return records.map { record in
            ChildInfo(
                uuid: record.childUUID,
                path: record.childPath,
                forkTimestamp: record.forkTimestamp,
                forkSnapshotSeq: record.forkSnapshotSeq
            )
        }
    }

    /// Whether this document has any children.
    public func hasChildren() throws -> Bool {
        let children = try fileStore.readChildren()
        return !children.isEmpty
    }

    /// Resolve the parent — check if the file still exists.
    public func resolveParent() throws -> ParentResolution {
        guard let parent = try parentInfo() else { return .noParent }

        // Check stored path
        if let path = parent.path, FileManager.default.fileExists(atPath: path) {
            return .found(URL(fileURLWithPath: path))
        }

        // Check registry for alternative path
        if let entry = RegistryManager.findByUUID(parent.uuid) {
            if FileManager.default.fileExists(atPath: entry.jntPath) {
                return .moved(URL(fileURLWithPath: entry.jntPath))
            }
        }

        return .unreachable(parent.uuid)
    }

    /// Walk the parent chain to find the root ancestor.
    public func findRoot(maxDepth: Int = 10) throws -> (UUID, URL?)? {
        var currentUUID: UUID
        var currentPath: String?

        if let uuidStr = try fileStore.readMetadata(key: "file_uuid"),
           let uuid = UUID(uuidString: uuidStr) {
            currentUUID = uuid
            currentPath = fileStore.url.path
        } else {
            return nil
        }

        for _ in 0..<maxDepth {
            guard let parent = try? parentInfoForFile(at: currentPath) else {
                return (currentUUID, currentPath.map { URL(fileURLWithPath: $0) })
            }
            currentUUID = parent.uuid
            currentPath = parent.path
        }

        return (currentUUID, currentPath.map { URL(fileURLWithPath: $0) })
    }

    private func parentInfoForFile(at path: String?) throws -> ParentInfo? {
        guard let path = path, FileManager.default.fileExists(atPath: path) else { return nil }
        let store = try JNTFileStore(url: URL(fileURLWithPath: path))
        defer { store.close() }

        guard let uuidStr = try store.readMetadata(key: "parent_uuid"),
              let uuid = UUID(uuidString: uuidStr) else { return nil }

        let parentPath = try store.readMetadata(key: "parent_path")
        return ParentInfo(uuid: uuid, path: parentPath, snapshotSeq: nil, forkTimestamp: nil)
    }
}
