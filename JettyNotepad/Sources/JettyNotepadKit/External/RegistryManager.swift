import Foundation

public struct RegistryEntry: Codable {
    public var jntPath: String
    public var isCompanion: Bool
    public var companionOriginalPath: String?
    public var displayName: String
    public var lastModifiedAt: String
    public var parentUUID: String?
    public var childUUIDs: [String]
    public var sizeBytes: Int64

    public init(jntPath: String, isCompanion: Bool, companionOriginalPath: String?,
                displayName: String, lastModifiedAt: String, parentUUID: String?,
                childUUIDs: [String], sizeBytes: Int64) {
        self.jntPath = jntPath
        self.isCompanion = isCompanion
        self.companionOriginalPath = companionOriginalPath
        self.displayName = displayName
        self.lastModifiedAt = lastModifiedAt
        self.parentUUID = parentUUID
        self.childUUIDs = childUUIDs
        self.sizeBytes = sizeBytes
    }
}

public class RegistryManager {
    public static let registryURL: URL = {
        ExternalFileManager.jettyNoteFolder.appendingPathComponent("registry.json")
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    public static func load() throws -> [String: RegistryEntry] {
        guard FileManager.default.fileExists(atPath: registryURL.path) else { return [:] }
        let data = try Data(contentsOf: registryURL)
        return try JSONDecoder().decode([String: RegistryEntry].self, from: data)
    }

    public static func save(_ entries: [String: RegistryEntry]) throws {
        try ExternalFileManager.ensureFolderStructure()
        let data = try encoder.encode(entries)
        try data.write(to: registryURL, options: .atomic)
    }

    public static func upsert(uuid: UUID, entry: RegistryEntry) throws {
        var entries = (try? load()) ?? [:]
        entries[uuid.uuidString] = entry
        try save(entries)
    }

    public static func findByOriginalPath(_ path: String) -> (UUID, RegistryEntry)? {
        guard let entries = try? load() else { return nil }
        for (uuidStr, entry) in entries {
            if entry.companionOriginalPath == path, let uuid = UUID(uuidString: uuidStr) {
                return (uuid, entry)
            }
        }
        return nil
    }

    public static func findByUUID(_ uuid: UUID) -> RegistryEntry? {
        guard let entries = try? load() else { return nil }
        return entries[uuid.uuidString]
    }

    public static func remove(uuid: UUID) throws {
        var entries = (try? load()) ?? [:]
        entries.removeValue(forKey: uuid.uuidString)
        try save(entries)
    }

    public static func allEntries() throws -> [String: RegistryEntry] {
        try load()
    }
}
