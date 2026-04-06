import Foundation

public class ExternalFileManager {
    public static let jettyNoteFolder: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("JettyNote")
    }()

    public static func companionURL(for uuid: UUID) -> URL {
        let prefix = String(uuid.uuidString.prefix(2).lowercased())
        return jettyNoteFolder
            .appendingPathComponent("companions")
            .appendingPathComponent(prefix)
            .appendingPathComponent("\(uuid.uuidString).jnt")
    }

    public static func ensureFolderStructure() throws {
        let fm = FileManager.default
        for sub in ["companions", "orphans"] {
            try fm.createDirectory(
                at: jettyNoteFolder.appendingPathComponent(sub),
                withIntermediateDirectories: true
            )
        }
    }

    /// Create or open a companion .jnt for an external file.
    /// Returns (companionStore, uuid, isNew).
    public static func openOrCreateCompanion(
        for externalURL: URL, content: String
    ) throws -> (JNTFileStore, UUID, Bool) {
        try ensureFolderStructure()

        // Check registry for existing companion
        if let (uuid, entry) = RegistryManager.findByOriginalPath(externalURL.path) {
            let companionURL = URL(fileURLWithPath: entry.jntPath)
            if FileManager.default.fileExists(atPath: companionURL.path) {
                let store = try JNTFileStore(url: companionURL)
                return (store, uuid, false)
            }
        }

        // Create new companion
        let uuid = UUID()
        let companionURL = self.companionURL(for: uuid)

        // Ensure the prefix directory exists
        try FileManager.default.createDirectory(
            at: companionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let store = try JNTFileStore.create(at: companionURL, content: content, uuid: uuid)
        try store.writeMetadata(key: "companion_original_path", value: externalURL.path)
        try store.writeMetadata(key: "companion_original_format",
                                value: externalURL.pathExtension.lowercased())

        // Register in registry
        let entry = RegistryEntry(
            jntPath: companionURL.path,
            isCompanion: true,
            companionOriginalPath: externalURL.path,
            displayName: JNTFileStore.displayNameFromContent(content),
            lastModifiedAt: ISO8601DateFormatter().string(from: Date()),
            parentUUID: nil,
            childUUIDs: [],
            sizeBytes: 0
        )
        try RegistryManager.upsert(uuid: uuid, entry: entry)

        return (store, uuid, true)
    }
}
