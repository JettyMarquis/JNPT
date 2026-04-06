import Foundation

// MARK: - Data Types

public struct JNTDocumentState {
    public let content: String
    public let cursorPosition: Int
    public let scrollPosition: Double
    public let createdAt: Date
    public let modifiedAt: Date
    public let originalLineEnding: String
}

public struct SnapshotSummary {
    public let seq: Int
    public let timestamp: Date
    public let snapshotType: String
    public let editSummary: String?
    public let contentLengthBefore: Int?
    public let contentLengthAfter: Int?
}

public struct ChildRecord {
    public let childUUID: UUID
    public let childPath: String?
    public let forkTimestamp: Date
    public let forkSnapshotSeq: Int?
}

// MARK: - JNTFileStore

public class JNTFileStore {
    public let db: SQLiteDatabase
    public let url: URL

    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Open an existing .jnt file
    public init(url: URL) throws {
        self.url = url
        self.db = try SQLiteDatabase(path: url.path)
    }

    /// Create a new .jnt file
    public static func create(at url: URL, content: String, uuid: UUID) throws -> JNTFileStore {
        let db = try SQLiteDatabase(path: url.path)
        try JNTSchema.migrate(db: db)

        let now = iso8601.string(from: Date())

        try db.inTransaction {
            // Insert document row
            try db.executeWithParams(
                """
                INSERT INTO document (id, content, cursor_position, scroll_position, created_at, modified_at)
                VALUES (1, ?1, 0, 0.0, ?2, ?3);
                """,
                params: [.text(content), .text(now), .text(now)]
            )

            // Insert metadata
            let metadataEntries: [(String, String)] = [
                ("format_version", "1"),
                ("file_uuid", uuid.uuidString),
                ("display_name_source", "firstLine"),
            ]
            for (key, value) in metadataEntries {
                try db.executeWithParams(
                    "INSERT INTO metadata (key, value) VALUES (?1, ?2);",
                    params: [.text(key), .text(value)]
                )
            }

            // Set display_name from first line
            let displayName = Self.displayNameFromContent(content)
            try db.executeWithParams(
                "INSERT INTO metadata (key, value) VALUES ('display_name', ?1);",
                params: [.text(displayName)]
            )
        }

        // Return a new store pointing at the file we just created
        let store = try JNTFileStore(url: url)
        return store
    }

    public func close() {
        db.close()
    }

    // MARK: - Document CRUD

    public func readContent() throws -> String {
        let rows = try db.query("SELECT content FROM document WHERE id = 1;")
        guard let row = rows.first, let content = row["content"]?.textValue else {
            throw JNTFileStoreError.noDocument
        }
        return content
    }

    public func readDocumentState() throws -> JNTDocumentState {
        let rows = try db.query("SELECT * FROM document WHERE id = 1;")
        guard let row = rows.first else { throw JNTFileStoreError.noDocument }

        guard let content = row["content"]?.textValue,
              let createdStr = row["created_at"]?.textValue,
              let modifiedStr = row["modified_at"]?.textValue else {
            throw JNTFileStoreError.corruptedData
        }

        let cursor = row["cursor_position"]?.intValue.map { Int($0) } ?? 0
        let scroll = row["scroll_position"]?.doubleValue ?? 0.0
        let lineEnding = row["original_line_ending"]?.textValue ?? "LF"

        let created = Self.iso8601.date(from: createdStr) ?? Date()
        let modified = Self.iso8601.date(from: modifiedStr) ?? Date()

        return JNTDocumentState(
            content: content,
            cursorPosition: cursor,
            scrollPosition: scroll,
            createdAt: created,
            modifiedAt: modified,
            originalLineEnding: lineEnding
        )
    }

    public func saveContent(_ content: String, cursor: Int, scroll: Double) throws {
        let now = Self.iso8601.string(from: Date())
        try db.executeWithParams(
            """
            UPDATE document SET content = ?1, cursor_position = ?2,
                scroll_position = ?3, modified_at = ?4
            WHERE id = 1;
            """,
            params: [.text(content), .int(Int64(cursor)), .double(scroll), .text(now)]
        )

        // Update display_name if source is firstLine
        if let source = try readMetadata(key: "display_name_source"), source == "firstLine" {
            let name = Self.displayNameFromContent(content)
            try writeMetadata(key: "display_name", value: name)
        }
    }

    // MARK: - Metadata

    public func readMetadata() throws -> [String: String] {
        let rows = try db.query("SELECT key, value FROM metadata;")
        var result: [String: String] = [:]
        for row in rows {
            if let k = row["key"]?.textValue, let v = row["value"]?.textValue {
                result[k] = v
            }
        }
        return result
    }

    public func readMetadata(key: String) throws -> String? {
        let rows = try db.query("SELECT value FROM metadata WHERE key = ?1;", params: [.text(key)])
        return rows.first?["value"]?.textValue
    }

    public func writeMetadata(key: String, value: String) throws {
        try db.executeWithParams(
            "INSERT OR REPLACE INTO metadata (key, value) VALUES (?1, ?2);",
            params: [.text(key), .text(value)]
        )
    }

    // MARK: - Snapshots (stubs for Phase 2)

    public func insertSnapshot(type: String, editSummary: String?, diffData: Data,
                               lengthBefore: Int, lengthAfter: Int) throws -> Int64 {
        let now = Self.iso8601.string(from: Date())
        return try db.insertReturningRowId(
            """
            INSERT INTO snapshots (timestamp, snapshot_type, edit_summary, diff_data,
                content_length_before, content_length_after)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6);
            """,
            params: [
                .text(now),
                .text(type),
                editSummary.map { SQLiteValue.text($0) } ?? .null,
                .blob(diffData),
                .int(Int64(lengthBefore)),
                .int(Int64(lengthAfter)),
            ]
        )
    }

    public func readSnapshotManifest() throws -> [SnapshotSummary] {
        let rows = try db.query(
            "SELECT seq, timestamp, snapshot_type, edit_summary, content_length_before, content_length_after FROM snapshots ORDER BY seq DESC;"
        )
        return rows.compactMap { row -> SnapshotSummary? in
            guard let seq = row["seq"]?.intValue,
                  let tsStr = row["timestamp"]?.textValue,
                  let type = row["snapshot_type"]?.textValue else { return nil }
            return SnapshotSummary(
                seq: Int(seq),
                timestamp: Self.iso8601.date(from: tsStr) ?? Date(),
                snapshotType: type,
                editSummary: row["edit_summary"]?.textValue,
                contentLengthBefore: row["content_length_before"]?.intValue.map { Int($0) },
                contentLengthAfter: row["content_length_after"]?.intValue.map { Int($0) }
            )
        }
    }

    public func readSnapshotDiff(seq: Int) throws -> Data {
        let rows = try db.query(
            "SELECT diff_data FROM snapshots WHERE seq = ?1;",
            params: [.int(Int64(seq))]
        )
        guard let row = rows.first, let data = row["diff_data"]?.blobValue else {
            throw JNTFileStoreError.snapshotNotFound(seq)
        }
        return data
    }

    public func snapshotCount() throws -> Int {
        let rows = try db.query("SELECT count(*) as cnt FROM snapshots;")
        return rows.first?["cnt"]?.intValue.map { Int($0) } ?? 0
    }

    // MARK: - Children (stubs for Phase 3)

    public func addChild(uuid: UUID, path: String, forkTimestamp: Date, forkSeq: Int) throws {
        try db.executeWithParams(
            """
            INSERT INTO children (child_uuid, child_path, fork_timestamp, fork_snapshot_seq)
            VALUES (?1, ?2, ?3, ?4);
            """,
            params: [
                .text(uuid.uuidString),
                .text(path),
                .text(Self.iso8601.string(from: forkTimestamp)),
                .int(Int64(forkSeq)),
            ]
        )
    }

    public func readChildren() throws -> [ChildRecord] {
        let rows = try db.query("SELECT * FROM children;")
        return rows.compactMap { row -> ChildRecord? in
            guard let uuidStr = row["child_uuid"]?.textValue,
                  let uuid = UUID(uuidString: uuidStr),
                  let tsStr = row["fork_timestamp"]?.textValue else { return nil }
            return ChildRecord(
                childUUID: uuid,
                childPath: row["child_path"]?.textValue,
                forkTimestamp: Self.iso8601.date(from: tsStr) ?? Date(),
                forkSnapshotSeq: row["fork_snapshot_seq"]?.intValue.map { Int($0) }
            )
        }
    }

    // MARK: - Helpers

    public static func displayNameFromContent(_ content: String) -> String {
        let firstLine = content.prefix(while: { $0 != "\n" && $0 != "\r" })
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Untitled" }
        if trimmed.count > 60 { return String(trimmed.prefix(57)) + "..." }
        return trimmed
    }
}

public enum JNTFileStoreError: Error, LocalizedError {
    case noDocument
    case corruptedData
    case snapshotNotFound(Int)

    public var errorDescription: String? {
        switch self {
        case .noDocument: return "No document row found in .jnt file"
        case .corruptedData: return "Corrupted data in .jnt file"
        case .snapshotNotFound(let seq): return "Snapshot \(seq) not found"
        }
    }
}
