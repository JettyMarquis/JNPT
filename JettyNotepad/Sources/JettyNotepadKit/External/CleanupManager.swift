import Foundation

public class CleanupManager {
    /// Find companions whose original file no longer exists.
    public static func scanForOrphans() throws -> [UUID] {
        let entries = try RegistryManager.allEntries()
        var orphans: [UUID] = []
        for (uuidStr, entry) in entries {
            guard entry.isCompanion, let origPath = entry.companionOriginalPath else { continue }
            if !FileManager.default.fileExists(atPath: origPath),
               let uuid = UUID(uuidString: uuidStr) {
                orphans.append(uuid)
            }
        }
        return orphans
    }

    /// Move companion .jnt files to the orphans directory.
    public static func moveToOrphans(_ uuids: [UUID]) throws {
        let fm = FileManager.default
        let orphansDir = ExternalFileManager.jettyNoteFolder.appendingPathComponent("orphans")
        try fm.createDirectory(at: orphansDir, withIntermediateDirectories: true)

        for uuid in uuids {
            guard let entry = RegistryManager.findByUUID(uuid) else { continue }
            let source = URL(fileURLWithPath: entry.jntPath)
            let dest = orphansDir.appendingPathComponent("\(uuid.uuidString).jnt")
            if fm.fileExists(atPath: source.path) {
                try fm.moveItem(at: source, to: dest)
            }
            // Update registry
            var updated = entry
            updated.jntPath = dest.path
            try RegistryManager.upsert(uuid: uuid, entry: updated)
        }
    }

    /// Delete orphans older than threshold.
    public static func purgeOldOrphans(olderThanDays: Int = 90) throws {
        let fm = FileManager.default
        let orphansDir = ExternalFileManager.jettyNoteFolder.appendingPathComponent("orphans")
        guard fm.fileExists(atPath: orphansDir.path) else { return }

        let threshold = Date().addingTimeInterval(-Double(olderThanDays) * 86400)
        let contents = try fm.contentsOfDirectory(at: orphansDir, includingPropertiesForKeys: [.contentModificationDateKey])

        for fileURL in contents where fileURL.pathExtension == "jnt" {
            let attrs = try fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            if let modDate = attrs.contentModificationDate, modDate < threshold {
                try fm.removeItem(at: fileURL)
                // Remove from registry
                let name = fileURL.deletingPathExtension().lastPathComponent
                if let uuid = UUID(uuidString: name) {
                    try RegistryManager.remove(uuid: uuid)
                }
            }
        }
    }

    /// Total bytes used by all .jnt files in JettyNote folder.
    public static func totalStorageBytes() throws -> Int64 {
        let fm = FileManager.default
        let baseDir = ExternalFileManager.jettyNoteFolder
        guard fm.fileExists(atPath: baseDir.path) else { return 0 }

        var total: Int64 = 0
        if let enumerator = fm.enumerator(at: baseDir, includingPropertiesForKeys: [.fileSizeKey]) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension == "jnt" {
                    let attrs = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                    total += Int64(attrs.fileSize ?? 0)
                }
            }
        }
        return total
    }

    /// Keep only the N most recent companions (by modified date).
    public static func cleanByCount(maxCount: Int) throws {
        let entries = try RegistryManager.allEntries()
        let companions = entries.filter { $0.value.isCompanion }
        guard companions.count > maxCount else { return }

        let sorted = companions.sorted { $0.value.lastModifiedAt > $1.value.lastModifiedAt }
        let toRemove = sorted.dropFirst(maxCount)
        for (uuidStr, entry) in toRemove {
            if let uuid = UUID(uuidString: uuidStr) {
                try? FileManager.default.removeItem(atPath: entry.jntPath)
                try RegistryManager.remove(uuid: uuid)
            }
        }
    }

    /// Delete all companions until total size is under limit.
    public static func cleanByCapacity(maxBytes: Int64) throws {
        var total = try totalStorageBytes()
        guard total > maxBytes else { return }

        let entries = try RegistryManager.allEntries()
        let sorted = entries.filter { $0.value.isCompanion }
            .sorted { $0.value.lastModifiedAt < $1.value.lastModifiedAt } // oldest first

        for (uuidStr, entry) in sorted {
            guard total > maxBytes else { break }
            let fileURL = URL(fileURLWithPath: entry.jntPath)
            if let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey]) {
                total -= Int64(attrs.fileSize ?? 0)
            }
            try? FileManager.default.removeItem(at: fileURL)
            if let uuid = UUID(uuidString: uuidStr) {
                try RegistryManager.remove(uuid: uuid)
            }
        }
    }

    /// Clear all snapshots for a specific file.
    public static func clearHistoryForFile(uuid: UUID) throws {
        guard let entry = RegistryManager.findByUUID(uuid) else { return }
        let db = try SQLiteDatabase(path: entry.jntPath)
        defer { db.close() }
        try db.execute("DELETE FROM snapshots;")
    }

    /// Remove everything in JettyNote folder and recreate structure.
    public static func clearAll() throws {
        let fm = FileManager.default
        let baseDir = ExternalFileManager.jettyNoteFolder
        if fm.fileExists(atPath: baseDir.path) {
            try fm.removeItem(at: baseDir)
        }
        try ExternalFileManager.ensureFolderStructure()
    }
}
