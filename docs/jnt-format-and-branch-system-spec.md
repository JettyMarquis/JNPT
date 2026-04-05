# JettyNotepad Technical Specification: .jnt File Format & Branch/Generation Tracking System

> Version: 1.0  
> Date: 2026-04-05  
> Status: Design (pre-implementation)  
> Depends on: PRD v1.0, Branch Save System Spec v1.0

---

## Table of Contents

1. [System 1: .jnt File Format Specification](#system-1-jnt-file-format-specification)
   - [1.1 Format Decision: ZIP Bundle](#11-format-decision-zip-bundle)
   - [1.2 Bundle Structure](#12-bundle-structure)
   - [1.3 Content Layer](#13-content-layer)
   - [1.4 Metadata Layer](#14-metadata-layer)
   - [1.5 History Layer](#15-history-layer)
   - [1.6 Graceful Degradation](#16-graceful-degradation)
   - [1.7 Quick Look Compatibility](#17-quick-look-compatibility)
   - [1.8 Size Budget Analysis](#18-size-budget-analysis)
   - [1.9 Data Structures](#19-data-structures)
2. [System 2: Branch & Generation Tracking System](#system-2-branch--generation-tracking-system)
   - [2.1 Save Operation State Machine](#21-save-operation-state-machine)
   - [2.2 Save As Operation State Machine](#22-save-as-operation-state-machine)
   - [2.3 Branch Detection & Mid-Tree Edit Handling](#23-branch-detection--mid-tree-edit-handling)
   - [2.4 History Folder Structure](#24-history-folder-structure)
   - [2.5 Source Chain Resolution](#25-source-chain-resolution)
   - [2.6 Cleanup System](#26-cleanup-system)
   - [2.7 Data Structures](#27-data-structures)
3. [Cross-System Integration](#cross-system-integration)
4. [Edge Cases & Failure Modes](#edge-cases--failure-modes)

---

## System 1: .jnt File Format Specification

### 1.1 Format Decision: ZIP Bundle

**Chosen format: ZIP bundle with `.jnt` extension.**

| Format | Pros | Cons | Verdict |
|--------|------|------|---------|
| **SQLite DB** | Single file, ACID transactions, efficient partial reads, built-in compression, battle-tested on macOS (Core Data uses it). Incremental writes without rewriting entire file. | Quick Look requires custom QL generator that must link SQLite. Cannot `unzip` to inspect. Corruption recovery harder -- requires `PRAGMA integrity_check`. Opaque binary format. | Finalist, but rejected for v1.0 due to Quick Look friction and inspection opacity. |
| **ZIP Bundle** | Quick Look gets plain text for free (UTI trick). Human-inspectable by renaming to `.zip`. Selective compression per entry. macOS Archive Utility native support. Textbundle precedent (Zettlr). Each layer is a separate file -- partial corruption is contained. | No ACID -- must write-rename atomically. Updating one entry rewrites entire archive (mitigated by small file sizes). No random access to middle of archive. | **Selected.** Best balance of Quick Look, debuggability, corruption resilience, and precedent. |
| **Custom Binary** | Maximum control over layout. Could optimize for append-only snapshot writes. | No tooling support. Must write parser from scratch. No Quick Look without QL generator. Maintenance burden disproportionate to team size. | Rejected. Engineering cost too high for the benefit. |

**Key mitigations for ZIP limitations:**
- Atomic write via write-to-temp-then-rename pattern (standard macOS `NSDocument` practice).
- File sizes stay small (sub-500KB target), so full rewrite cost is negligible.
- If future profiling reveals write latency issues, migration path to SQLite is straightforward since layers are cleanly separated.

### 1.2 Bundle Structure

```
document.jnt (ZIP archive)
+-- content.txt              # Current text content, UTF-8, no BOM
+-- metadata.json             # File identity, timestamps, source chain
+-- history/
|   +-- manifest.json         # Snapshot index: ordered list of snapshot metadata
|   +-- snapshots/
|       +-- 001.rdiff         # Reverse diff: applying to snapshot 002 yields snapshot 001
|       +-- 002.rdiff         # Reverse diff: applying to current content yields snapshot 002
|       +-- ...               # Up to 100 entries (oldest = 001)
+-- quicklook/
    +-- Preview.txt           # Copy of content.txt for macOS Quick Look (see 1.7)
```

**File naming convention:** Snapshot files are zero-padded 3-digit numbers. The highest number is the most recent snapshot. Current content is always `content.txt` (not a snapshot).

**Compression:** ZIP entries use DEFLATE for `history/snapshots/*.rdiff` and STORE (no compression) for `content.txt`, `metadata.json`, and `quicklook/Preview.txt`. Rationale: text diffs compress well; the other files are small and benefit from direct readability.

### 1.3 Content Layer

**File:** `content.txt`

- Encoding: UTF-8, no BOM
- Line endings: LF (normalized on save; original line ending style recorded in metadata for export fidelity)
- Contains exactly what the user sees in the editor at the time of last save
- No markup, no metadata, no headers -- pure text content

```
This is the actual document text.
The user sees exactly this in the editor.
```

**Why plain text, not JSON-wrapped:** Maximizes Quick Look compatibility, simplifies corruption recovery (just extract `content.txt`), and avoids escaping issues with special characters.

### 1.4 Metadata Layer

**File:** `metadata.json`

```json
{
  "formatVersion": 1,
  "fileUUID": "550e8400-e29b-41d4-a716-446655440000",
  "createdAt": "2026-04-05T14:30:00.000Z",
  "lastModifiedAt": "2026-04-05T15:45:12.000Z",
  "displayName": "Meeting notes for Q2 planning",
  "displayNameSource": "firstLine",
  "originalLineEnding": "LF",
  "sourceChain": {
    "parentFileUUID": "339a2e00-b1c4-4f8e-9d12-abcdef123456",
    "parentFilePath": "/Users/vox/Documents/draft-v1.jnt",
    "parentSnapshotIndex": 42,
    "parentForkTimestamp": "2026-04-05T14:30:00.000Z",
    "children": [
      {
        "childFileUUID": "771f9200-c3d5-5a9f-ae23-bcdef2345678",
        "childFilePath": "/Users/vox/Documents/draft-v3.jnt",
        "childForkTimestamp": "2026-04-05T16:00:00.000Z",
        "childForkSnapshotIndex": 67
      }
    ]
  },
  "companionOf": null,
  "stats": {
    "totalSnapshots": 47,
    "oldestSnapshotTimestamp": "2026-04-05T14:30:00.000Z",
    "totalEditsAggregated": 312
  }
}
```

**Field specifications:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `formatVersion` | `int` | Yes | Always `1` for this spec. Future versions increment. Reader must reject unknown major versions but attempt best-effort for minor differences. |
| `fileUUID` | `string (UUID v4)` | Yes | Globally unique. Generated once at file creation. Never changes, even if file is renamed or moved. |
| `createdAt` | `string (ISO 8601)` | Yes | Timestamp of file creation. Immutable after creation. |
| `lastModifiedAt` | `string (ISO 8601)` | Yes | Updated on every save (manual or auto). |
| `displayName` | `string` | Yes | Auto-generated from first line of content. Chinese: first 10 chars. English: first 8 words. Truncated with ellipsis if longer. |
| `displayNameSource` | `enum` | Yes | `"firstLine"` (auto) or `"userSet"` (if user explicitly names it). |
| `originalLineEnding` | `enum` | Yes | `"LF"`, `"CRLF"`, or `"CR"`. Preserved for export fidelity. |
| `sourceChain.parentFileUUID` | `string?` | No | UUID of the file this was forked from via Save As. `null` for original documents. |
| `sourceChain.parentFilePath` | `string?` | No | Last known filesystem path of parent. Used for UI display and reconnection attempts. Not authoritative -- UUID is the true identity. |
| `sourceChain.parentSnapshotIndex` | `int?` | No | Which snapshot in the parent's history this fork originated from. `null` if forked from current content (not from history). |
| `sourceChain.parentForkTimestamp` | `string?` | No | When the fork occurred. |
| `sourceChain.children` | `array` | Yes | Array of child references. Empty array `[]` for leaf documents. |
| `companionOf` | `object?` | No | If this `.jnt` is a companion file for an external document (see 2.4). Contains `{ "originalPath": string, "originalFormat": string }`. |
| `stats` | `object` | Yes | Computed statistics for quick display without parsing history. |

### 1.5 History Layer

**Design: reverse diff chain from current content.**

The current content is stored in full as `content.txt`. Each snapshot stores a reverse diff that, when applied to the next-newer version, reproduces the older version. This means:

- To view the most recent snapshot: apply `snapshots/NNN.rdiff` to `content.txt`
- To view snapshot N: apply diffs from NNN down to N sequentially
- Viewing older snapshots is progressively more expensive (more diffs to apply)

This is the correct trade-off for a notepad app where users almost always want recent history, not ancient history.

**Diff format: Myers diff on lines, encoded as a compact JSON structure.**

Each `.rdiff` file:

```json
{
  "snapshotIndex": 47,
  "timestamp": "2026-04-05T15:42:00.000Z",
  "snapshotType": "manualSave",
  "editSummary": "paste",
  "bytesBefore": 2048,
  "bytesAfter": 2156,
  "ops": [
    { "op": "keep", "lines": 5 },
    { "op": "delete", "lines": ["This line was removed.", "And this one too."] },
    { "op": "keep", "lines": 3 },
    { "op": "insert", "lines": ["This old line existed before the edit."] },
    { "op": "keep", "lines": 12 }
  ]
}
```

**Snapshot metadata fields:**

| Field | Type | Description |
|-------|------|-------------|
| `snapshotIndex` | `int` | Monotonically increasing. Never reused within a file's lifetime. |
| `timestamp` | `ISO 8601` | When this snapshot was captured. |
| `snapshotType` | `enum` | `"manualSave"`, `"autoSave"`, `"sessionBoundary"`, `"forkPoint"` |
| `editSummary` | `enum` | `"type"`, `"paste"`, `"delete"`, `"replace"`, `"mixed"`, `"undo"`, `"redo"` |
| `bytesBefore` | `int` | Content size before this edit (the snapshot's reconstructed state). |
| `bytesAfter` | `int` | Content size after this edit (the next-newer state). |
| `ops` | `array` | Ordered list of diff operations. |

**Diff operations:**

| Op | Meaning | Data |
|----|---------|------|
| `keep` | Lines unchanged | `lines: int` (count of lines to skip) |
| `delete` | Lines present in older version but removed in newer | `lines: string[]` (the deleted line contents) |
| `insert` | Lines present in newer version but not in older | `lines: string[]` (the inserted line contents) |

**Why line-level diffs, not character-level:**
- Simpler to implement and debug
- Line-level diffs compress very well with DEFLATE (repetitive structure)
- Character-level (diff-match-patch) saves ~20-30% more space but adds complexity
- For a 10KB document with 100 snapshots, the difference is ~50KB vs ~70KB -- both well within budget
- Migration path: `formatVersion` 2 could switch to character-level if needed

**Manifest file:** `history/manifest.json`

```json
{
  "snapshotCount": 47,
  "oldestIndex": 1,
  "newestIndex": 47,
  "totalOpsBytes": 34521,
  "snapshots": [
    {
      "index": 1,
      "timestamp": "2026-04-05T14:30:00.000Z",
      "type": "sessionBoundary",
      "bytesBefore": 0
    },
    {
      "index": 2,
      "timestamp": "2026-04-05T14:31:15.000Z",
      "type": "autoSave",
      "bytesBefore": 256
    }
  ]
}
```

The manifest provides a lightweight index so the app can display the history timeline without parsing every `.rdiff` file. It duplicates some fields from individual snapshots -- this is intentional for performance.

**Snapshot aggregation rules (when to create a new snapshot):**

| Trigger | Snapshot Type | Notes |
|---------|--------------|-------|
| User presses Cmd+S | `manualSave` | Always creates a snapshot |
| Auto-save timer fires (default 1 min) | `autoSave` | Only if content changed since last snapshot |
| App loses focus | `autoSave` | Only if content changed |
| Tab is closed | `sessionBoundary` | Always, even if unchanged (marks session end) |
| App launch restores session | `sessionBoundary` | Marks session start |
| User executes Save As | `forkPoint` | Marks the exact state that was forked |
| Idle > 5 seconds after burst of edits | `autoSave` | Captures natural pause boundaries |

**Snapshot eviction (when count exceeds 100):**

When snapshot count reaches 100 and a new snapshot must be added:

1. **Priority eviction order:**
   - `autoSave` snapshots that are adjacent to another snapshot within 2 minutes -- merge the older one
   - `autoSave` snapshots older than 7 days -- thin to one per hour
   - `autoSave` snapshots older than 30 days -- thin to one per day
2. **Never evict:** `manualSave`, `sessionBoundary`, `forkPoint` (unless they exceed 80% of slots, in which case apply time-thinning to `sessionBoundary`)
3. **Eviction merges:** When evicting snapshot N, its diff is composed with snapshot N+1's diff to maintain chain integrity

### 1.6 Graceful Degradation

The format is designed so partial corruption yields partial recovery:

| Corruption Scenario | Recovery |
|---------------------|----------|
| ZIP cannot be opened at all | Attempt to scan raw bytes for `content.txt` entry (ZIP local file headers are self-describing). Fall back to treating entire file as raw text. |
| `content.txt` intact, everything else corrupt | Open document with current content. No history, no metadata. Generate new UUID and metadata. |
| `metadata.json` corrupt | Open with content + history. Regenerate metadata (new UUID, lose source chain). Warn user. |
| `history/` directory corrupt or missing | Open with content + metadata. History unavailable. Warn user. |
| Single `.rdiff` file corrupt | History available up to that point. Snapshots older than the corrupt entry are unreachable. Warn user. |
| `content.txt` missing but history exists | Attempt to reconstruct from most recent snapshot + diff. If impossible, report error. |
| `quicklook/Preview.txt` missing | No impact on app. Quick Look preview unavailable. Regenerated on next save. |

**Implementation:** The file reader should use a try-recover pattern for each layer independently. Never let metadata/history corruption prevent opening the document text.

### 1.7 Quick Look Compatibility

macOS Quick Look can preview text files inside ZIP archives if the UTI is correctly configured.

**Strategy:**

1. Register `.jnt` UTI as conforming to `com.pkware.zip-archive` and `public.data`
2. Include `quicklook/Preview.txt` as a plain text preview file
3. Implement a Quick Look generator (QLGenerator / QuickLookPreviewExtension) that:
   - Opens the ZIP
   - Reads `quicklook/Preview.txt`
   - Renders it as plain text

**Why a separate `Preview.txt` instead of reading `content.txt`:**
- Quick Look generators should be fast and low-memory
- Having a dedicated preview file avoids navigating into the ZIP's root and parsing alongside history entries
- `Preview.txt` is an exact copy of `content.txt`, updated on every save
- Redundancy cost: negligible (duplicate of a small text file)

**UTI declaration (Info.plist):**

```xml
<dict>
  <key>UTTypeIdentifier</key>
  <string>com.jettymarquis.jettynotepad.jnt</string>
  <key>UTTypeDescription</key>
  <string>JettyNotepad Document</string>
  <key>UTTypeConformsTo</key>
  <array>
    <string>public.data</string>
    <string>public.content</string>
  </array>
  <key>UTTypeTagSpecification</key>
  <dict>
    <key>public.filename-extension</key>
    <array>
      <string>jnt</string>
    </array>
  </dict>
</dict>
```

### 1.8 Size Budget Analysis

**Scenario: 10KB text file, 100 snapshots, typical editing pattern.**

Assumptions:
- Average edit changes ~5% of content per snapshot
- 10KB content = ~250 lines at 40 chars/line
- Each diff touches ~12 lines on average
- Each diff op line is ~50 bytes as JSON
- DEFLATE compression ratio on diff JSON: ~60% reduction

Calculation:

| Component | Raw Size | Compressed | Notes |
|-----------|----------|------------|-------|
| `content.txt` | 10 KB | 10 KB (STORE) | Uncompressed for readability |
| `quicklook/Preview.txt` | 10 KB | 10 KB (STORE) | Duplicate of content |
| `metadata.json` | ~1 KB | 1 KB (STORE) | Small, not worth compressing |
| `history/manifest.json` | ~8 KB | ~3 KB (DEFLATE) | 100 entries at ~80 bytes each |
| `history/snapshots/*.rdiff` x 100 | ~120 KB total | ~48 KB (DEFLATE) | 12 lines x 50 bytes x 100 / 0.5 raw, then 60% compression |
| ZIP overhead | ~5 KB | 5 KB | Central directory, local headers |
| **Total** | **~154 KB** | **~77 KB** | |

**Result: ~77 KB for a 10KB document with 100 snapshots. Well within the 500KB budget.**

Worst case (large diffs, 50% content change per snapshot):

| Component | Compressed |
|-----------|------------|
| content + preview + metadata | 21 KB |
| manifest | 3 KB |
| 100 large diffs | ~200 KB |
| overhead | 5 KB |
| **Total** | **~229 KB** |

Still within budget. The 500KB ceiling would only be reached with documents >40KB that have massive diffs every snapshot -- an unlikely usage pattern for a notepad app.

### 1.9 Data Structures (Swift)

```swift
import Foundation

// MARK: - Format Constants

enum JNTFormat {
    static let currentVersion = 1
    static let maxSnapshots = 100
    static let contentPath = "content.txt"
    static let metadataPath = "metadata.json"
    static let manifestPath = "history/manifest.json"
    static let snapshotDir = "history/snapshots"
    static let previewPath = "quicklook/Preview.txt"
}

// MARK: - Content Layer

/// The content layer is a plain UTF-8 string. No wrapper struct needed.
/// Read/write as Data with .utf8 encoding.

// MARK: - Metadata Layer

struct JNTMetadata: Codable {
    let formatVersion: Int
    let fileUUID: UUID
    let createdAt: Date
    var lastModifiedAt: Date
    var displayName: String
    var displayNameSource: DisplayNameSource
    var originalLineEnding: LineEnding
    var sourceChain: SourceChain
    var companionOf: CompanionInfo?
    var stats: DocumentStats

    enum DisplayNameSource: String, Codable {
        case firstLine
        case userSet
    }

    enum LineEnding: String, Codable {
        case lf = "LF"
        case crlf = "CRLF"
        case cr = "CR"
    }
}

struct SourceChain: Codable {
    var parentFileUUID: UUID?
    var parentFilePath: String?
    var parentSnapshotIndex: Int?
    var parentForkTimestamp: Date?
    var children: [ChildReference]
}

struct ChildReference: Codable {
    let childFileUUID: UUID
    var childFilePath: String
    let childForkTimestamp: Date
    let childForkSnapshotIndex: Int?
}

struct CompanionInfo: Codable {
    var originalPath: String
    var originalFormat: String  // "txt", "md", "log", etc.
}

struct DocumentStats: Codable {
    var totalSnapshots: Int
    var oldestSnapshotTimestamp: Date?
    var totalEditsAggregated: Int
}

// MARK: - History Layer

struct SnapshotManifest: Codable {
    var snapshotCount: Int
    var oldestIndex: Int
    var newestIndex: Int
    var totalOpsBytes: Int
    var snapshots: [SnapshotSummary]
}

struct SnapshotSummary: Codable {
    let index: Int
    let timestamp: Date
    let type: SnapshotType
    let bytesBefore: Int
}

enum SnapshotType: String, Codable {
    case manualSave
    case autoSave
    case sessionBoundary
    case forkPoint
}

struct Snapshot: Codable {
    let snapshotIndex: Int
    let timestamp: Date
    let snapshotType: SnapshotType
    let editSummary: EditSummary
    let bytesBefore: Int
    let bytesAfter: Int
    let ops: [DiffOp]
}

enum EditSummary: String, Codable {
    case type
    case paste
    case delete
    case replace
    case mixed
    case undo
    case redo
}

enum DiffOp: Codable {
    case keep(lines: Int)
    case delete(lines: [String])
    case insert(lines: [String])

    // Custom Codable for compact JSON representation
    enum CodingKeys: String, CodingKey {
        case op, lines
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keep(let count):
            try container.encode("keep", forKey: .op)
            try container.encode(count, forKey: .lines)
        case .delete(let content):
            try container.encode("delete", forKey: .op)
            try container.encode(content, forKey: .lines)
        case .insert(let content):
            try container.encode("insert", forKey: .op)
            try container.encode(content, forKey: .lines)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let op = try container.decode(String.self, forKey: .op)
        switch op {
        case "keep":
            let count = try container.decode(Int.self, forKey: .lines)
            self = .keep(lines: count)
        case "delete":
            let content = try container.decode([String].self, forKey: .lines)
            self = .delete(lines: content)
        case "insert":
            let content = try container.decode([String].self, forKey: .lines)
            self = .insert(lines: content)
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [CodingKeys.op], debugDescription: "Unknown op: \(op)")
            )
        }
    }
}

// MARK: - Diff Engine

/// Applies a reverse diff to reconstruct an older version from a newer one.
/// `newerContent` is split by lines; ops are applied sequentially.
func applyReverseDiff(newerContent: String, diff: Snapshot) -> String {
    var newerLines = newerContent.components(separatedBy: "\n")
    var result: [String] = []
    var cursor = 0

    for op in diff.ops {
        switch op {
        case .keep(let count):
            result.append(contentsOf: newerLines[cursor..<(cursor + count)])
            cursor += count
        case .delete(let lines):
            // These lines exist in the older version but not the newer
            // "delete" in reverse diff means "insert into reconstruction"
            result.append(contentsOf: lines)
        case .insert(let lines):
            // These lines exist in the newer version but not the older
            // "insert" in reverse diff means "skip in newer"
            // Verify they match, then skip
            cursor += lines.count
        }
    }

    // Append any remaining lines (keep-to-end)
    if cursor < newerLines.count {
        result.append(contentsOf: newerLines[cursor...])
    }

    return result.joined(separator: "\n")
}

// MARK: - File Reader with Graceful Degradation

struct JNTReadResult {
    var content: String?
    var metadata: JNTMetadata?
    var manifest: SnapshotManifest?
    var warnings: [JNTWarning]
    var isFullyIntact: Bool {
        content != nil && metadata != nil && manifest != nil && warnings.isEmpty
    }
}

enum JNTWarning {
    case metadataCorrupt(Error)
    case historyCorrupt(Error)
    case snapshotCorrupt(index: Int, Error)
    case previewMissing
    case metadataRegenerated
    case unknownFormatVersion(Int)
}
```

---

## System 2: Branch & Generation Tracking System

### 2.1 Save Operation State Machine

```
                    +------------------+
                    |  User triggers   |
                    |   Cmd+S / Auto   |
                    +--------+---------+
                             |
                    +--------v---------+
                    | Is file a .jnt?  |
                    +--------+---------+
                        |          |
                       Yes         No (external file)
                        |          |
              +---------v----+  +--v-----------------+
              | Update .jnt  |  | Save original      |
              | in place     |  | format to its path  |
              +---------+----+  +--+-----------------+
                        |          |
                        |     +----v-----------------+
                        |     | Update/create         |
                        |     | companion .jnt in     |
                        |     | JettyNote folder      |
                        |     +----+-----------------+
                        |          |
                    +---v----------v---+
                    | Create snapshot  |
                    | (if content      |
                    |  changed)        |
                    +--------+---------+
                             |
                    +--------v---------+
                    | Evict oldest     |
                    | snapshot if      |
                    | count > 100      |
                    +--------+---------+
                             |
                    +--------v---------+
                    | Update metadata: |
                    | lastModifiedAt,  |
                    | displayName,     |
                    | stats            |
                    +--------+---------+
                             |
                    +--------v---------+
                    | Atomic write     |
                    | (temp + rename)  |
                    +------------------+
```

**Save operation pseudocode:**

```swift
func save(document: Document) throws {
    let content = document.currentContent
    let previousContent = document.lastSavedContent

    // Step 1: Handle external file format
    if let companion = document.metadata.companionOf {
        // Save in original format
        try content.write(
            toFile: companion.originalPath,
            encoding: document.metadata.originalLineEnding
        )
    }

    // Step 2: Create snapshot if content changed
    if content != previousContent {
        let diff = computeReverseDiff(from: content, to: previousContent)
        let snapshot = Snapshot(
            snapshotIndex: document.nextSnapshotIndex(),
            timestamp: Date(),
            snapshotType: document.saveTriggeredBy.toSnapshotType(),
            editSummary: document.currentEditClassification(),
            bytesBefore: previousContent.utf8.count,
            bytesAfter: content.utf8.count,
            ops: diff
        )
        document.addSnapshot(snapshot)  // Handles eviction if > 100
    }

    // Step 3: Update metadata
    document.metadata.lastModifiedAt = Date()
    document.metadata.displayName = deriveDisplayName(from: content)
    document.metadata.stats.totalSnapshots = document.snapshotCount

    // Step 4: Atomic write
    let tempURL = document.fileURL.appendingPathExtension("tmp")
    try writeJNTBundle(to: tempURL, content: content, metadata: document.metadata,
                       manifest: document.manifest, snapshots: document.snapshots)
    try FileManager.default.replaceItem(
        at: document.fileURL, withItemAt: tempURL,
        backupItemName: nil, resultingItemURL: nil
    )

    document.lastSavedContent = content
}
```

**Key invariants of Save:**
- File UUID never changes
- File path never changes
- No new parent-child relationships created
- Source chain unchanged
- Undo/Redo stack preserved in memory (not persisted)

### 2.2 Save As Operation State Machine

```
                    +-------------------+
                    |  User triggers    |
                    |   Save As...      |
                    +--------+----------+
                             |
                    +--------v----------+
                    | User chooses new  |
                    | path + format     |
                    +--------+----------+
                             |
                +------------v-----------+
                | Is target format .jnt? |
                +-----+----------+-------+
                     Yes          No
                      |           |
          +-----------v--+  +-----v--------------+
          | Create new   |  | Save target format |
          | .jnt file    |  | to chosen path     |
          +-----------+--+  +-----+--------------+
                      |           |
                      |     +-----v--------------+
                      |     | Create companion   |
                      |     | .jnt in JettyNote  |
                      |     | folder             |
                      |     +-----+--------------+
                      |           |
                +-----v-----------v------+
                | Generate new UUID for  |
                | the new file           |
                +--------+---------------+
                         |
                +--------v---------------+
                | Record fork point in   |
                | PARENT file:           |
                | - Add child UUID       |
                | - Add child path       |
                | - Create forkPoint     |
                |   snapshot             |
                +--------+---------------+
                         |
                +--------v---------------+
                | Initialize NEW file:   |
                | - Full content copy    |
                | - Fresh history        |
                |   (snapshot 0 =        |
                |    forkPoint)          |
                | - Parent UUID ref      |
                | - Parent path          |
                | - Parent snapshot idx  |
                +--------+---------------+
                         |
                +--------v---------------+
                | Atomic write BOTH      |
                | files (parent first,   |
                | then child)            |
                +--------+---------------+
                         |
                +--------v---------------+
                | Switch active document |
                | to the new file        |
                +------------------------+
```

**Save As pseudocode:**

```swift
func saveAs(document: Document, newPath: URL, targetFormat: FileFormat) throws {
    let content = document.currentContent
    let now = Date()

    // Step 1: Create fork-point snapshot in parent
    let forkSnapshot = Snapshot(
        snapshotIndex: document.nextSnapshotIndex(),
        timestamp: now,
        snapshotType: .forkPoint,
        editSummary: .mixed,
        bytesBefore: document.lastSavedContent.utf8.count,
        bytesAfter: content.utf8.count,
        ops: computeReverseDiff(from: content, to: document.lastSavedContent)
    )
    document.addSnapshot(forkSnapshot)

    // Step 2: Generate new file identity
    let newUUID = UUID()
    let parentSnapshotIndex = forkSnapshot.snapshotIndex

    // Step 3: Build new file metadata
    let newMetadata = JNTMetadata(
        formatVersion: JNTFormat.currentVersion,
        fileUUID: newUUID,
        createdAt: now,
        lastModifiedAt: now,
        displayName: deriveDisplayName(from: content),
        displayNameSource: .firstLine,
        originalLineEnding: document.metadata.originalLineEnding,
        sourceChain: SourceChain(
            parentFileUUID: document.metadata.fileUUID,
            parentFilePath: document.fileURL.path,
            parentSnapshotIndex: parentSnapshotIndex,
            parentForkTimestamp: now,
            children: []
        ),
        companionOf: targetFormat != .jnt
            ? CompanionInfo(originalPath: newPath.path,
                            originalFormat: targetFormat.rawValue)
            : nil,
        stats: DocumentStats(
            totalSnapshots: 1,
            oldestSnapshotTimestamp: now,
            totalEditsAggregated: 0
        )
    )

    // Step 4: Build initial snapshot for new file (the fork-point state)
    let initialSnapshot = Snapshot(
        snapshotIndex: 0,
        timestamp: now,
        snapshotType: .forkPoint,
        editSummary: .mixed,
        bytesBefore: 0,
        bytesAfter: content.utf8.count,
        ops: []  // Snapshot 0 has no diff -- full content is in content.txt
    )

    // Step 5: Update parent's source chain
    let childRef = ChildReference(
        childFileUUID: newUUID,
        childFilePath: newPath.path,
        childForkTimestamp: now,
        childForkSnapshotIndex: parentSnapshotIndex
    )
    document.metadata.sourceChain.children.append(childRef)

    // Step 6: Write external format if needed
    if targetFormat != .jnt {
        try content.write(toFile: newPath, encoding: document.metadata.originalLineEnding)
    }

    // Step 7: Atomic write parent (updated source chain)
    try atomicWriteJNT(document)

    // Step 8: Atomic write new child .jnt
    let childJNTPath = targetFormat == .jnt
        ? newPath
        : companionJNTPath(for: newPath)
    try writeJNTBundle(
        to: childJNTPath,
        content: content,
        metadata: newMetadata,
        manifest: SnapshotManifest(
            snapshotCount: 1,
            oldestIndex: 0,
            newestIndex: 0,
            totalOpsBytes: 0,
            snapshots: [SnapshotSummary(
                index: 0, timestamp: now, type: .forkPoint, bytesBefore: 0
            )]
        ),
        snapshots: [initialSnapshot]
    )

    // Step 9: Switch active document to child
    document.switchTo(path: childJNTPath, metadata: newMetadata)
}
```

### 2.3 Branch Detection & Mid-Tree Edit Handling

**State machine for branch detection:**

```
                    +------------------+
                    | User opens file  |
                    +--------+---------+
                             |
                    +--------v---------+
                    | Read metadata    |
                    | sourceChain      |
                    +--------+---------+
                             |
                    +--------v---------+
                    | children.count   |
                    | > 0 ?            |
                    +----+--------+----+
                        Yes        No
                         |          |
              +----------v---+  +---v-----------+
              | Set flag:    |  | Normal edit   |
              | hasDownstream|  | mode          |
              | = true       |  +---------------+
              +----------+---+
                         |
                    +----v-------------+
                    | User makes first |
                    | edit to content  |
                    +----+-------------+
                         |
                    +----v-----------------------------+
                    | Show non-modal alert:            |
                    |                                  |
                    | "This document has N downstream  |
                    |  versions created from it.       |
                    |  Editing here may make those     |
                    |  versions' history references    |
                    |  to this file incomplete."       |
                    |                                  |
                    | [Save As New Branch] [Continue]  |
                    +----+------------------+----------+
                         |                  |
              +----------v---+    +---------v----------+
              | Trigger      |    | Set flag:          |
              | Save As flow |    | midTreeEditAck     |
              | (2.2)        |    | = true             |
              +--------------+    | (suppress future   |
                                  |  warnings for this |
                                  |  session)          |
                                  +--------------------+
```

**Implementation notes:**

- The warning is shown only once per editing session per document. Once the user chooses "Continue", the flag `midTreeEditAck` is set and no further warnings appear until the document is closed and reopened.
- The warning is non-modal (a banner or sheet, not a blocking dialog) -- it does not prevent the user from continuing to type.
- The [Save As New Branch] button is visually emphasized (primary button style). [Continue] is secondary.
- The warning text avoids technical jargon. "downstream versions" is the most technical term used; the PRD requests accessible language.
- The child count N is computed from `sourceChain.children.count`. It counts all children, not just verified-reachable ones.

**Edge case -- editing a mid-tree file from history view:**

If the user is viewing an old snapshot (not current content) and wants to "branch from here":

```
                    +-------------------+
                    | User views        |
                    | snapshot #42      |
                    +--------+----------+
                             |
                    +--------v----------+
                    | User clicks       |
                    | "Branch From Here"|
                    +--------+----------+
                             |
                    +--------v----------+
                    | Reconstruct       |
                    | content at #42    |
                    | (apply diffs)     |
                    +--------+----------+
                             |
                    +--------v----------+
                    | Trigger Save As   |
                    | with:             |
                    | - content = #42   |
                    | - parentSnapshot  |
                    |   Index = 42      |
                    +-------------------+
```

This creates a new child file whose `parentSnapshotIndex` is 42, not the current head. The parent file is unchanged.

### 2.4 History Folder Structure

```
~/Documents/JettyNote/
+-- registry.json                          # Central index of all tracked files
+-- companions/                            # Companion .jnt files for external documents
|   +-- <UUID-prefix-2>/<UUID>.jnt         # Sharded by first 2 chars of UUID
|   +-- ab/ab3f9c00-...jnt
|   +-- cd/cde41200-...jnt
+-- orphans/                               # .jnt files whose originals were deleted/moved
|   +-- <UUID>.jnt                         # Moved here during cleanup scan
+-- settings.json                          # Folder-level settings (retention policy, etc.)
```

**Why shard companions by UUID prefix:**
- Avoids flat directory with thousands of files (macOS Finder performance degrades >10K items)
- UUID v4 gives uniform distribution across 256 buckets
- 2-char prefix supports up to ~65K files per bucket before needing deeper sharding

**Registry file:** `registry.json`

```json
{
  "registryVersion": 1,
  "lastScanAt": "2026-04-05T15:00:00.000Z",
  "entries": {
    "550e8400-e29b-41d4-a716-446655440000": {
      "jntPath": "/Users/vox/Documents/notes/meeting.jnt",
      "isCompanion": false,
      "companionOriginalPath": null,
      "displayName": "Meeting notes for Q2",
      "lastModifiedAt": "2026-04-05T15:45:12.000Z",
      "parentUUID": null,
      "childUUIDs": ["771f9200-c3d5-5a9f-ae23-bcdef2345678"],
      "sizeBytes": 78342
    },
    "ab3f9c00-1234-5678-9abc-def012345678": {
      "jntPath": "~/Documents/JettyNote/companions/ab/ab3f9c00-1234-5678-9abc-def012345678.jnt",
      "isCompanion": true,
      "companionOriginalPath": "/Users/vox/Desktop/todo.txt",
      "displayName": "Weekly TODO list",
      "lastModifiedAt": "2026-04-05T14:00:00.000Z",
      "parentUUID": null,
      "childUUIDs": [],
      "sizeBytes": 12400
    }
  }
}
```

**Registry update triggers:**
- Every Save and Save As updates the registry entry
- App launch performs a lightweight registry validation (check that registered paths still exist)
- Full scan (checking for orphans) runs on explicit user request or weekly background check

**Companion file naming convention:**

For an external file at `/Users/vox/Desktop/report.txt`:
- Companion .jnt: `~/Documents/JettyNote/companions/<2-char>/<UUID>.jnt`
- The companion's `metadata.json` contains `companionOf.originalPath = "/Users/vox/Desktop/report.txt"`
- The registry maps UUID <-> original path for fast lookup

**Why UUID-based names instead of mirroring the original path:**
- Original paths can change (user moves file). UUID is stable.
- Avoids filesystem-illegal characters in paths.
- Avoids collisions when two files in different directories have the same name.

### 2.5 Source Chain Resolution

**Problem: files move, get renamed, or get deleted. The source chain stores paths as hints, but UUIDs are the true identity.**

#### Scenario 1: Parent file moved/renamed

```
Detection:  Child opens, reads parentFilePath, file not found at that path.
Resolution:
  1. Look up parentFileUUID in registry.json
  2. If found in registry with updated path -> update child's parentFilePath, continue
  3. If not found in registry -> scan ~/Documents/JettyNote/ for .jnt files
     with matching UUID (expensive, only on explicit user request)
  4. If still not found -> mark parent as "unreachable" in UI
     - Show: "Parent document (draft-v1) has been moved or deleted."
     - Source chain remains intact with stale path
     - History within this file is unaffected
     - User can manually re-link if they locate the parent
```

#### Scenario 2: Child file moved/renamed

```
Detection:  Parent opens, reads childFilePath, file not found at that path.
Resolution:
  1. Look up childFileUUID in registry.json
  2. If found -> update parent's childFilePath
  3. If not found -> mark child as "unreachable"
     - Show grayed-out child in source chain view
     - "Version 'draft-v3' has been moved or deleted"
     - Do NOT remove from children array (preserves historical record)
```

#### Scenario 3: Parent file deleted

```
Detection:  Same as Scenario 1, but file is confirmed gone.
Resolution:
  - Child becomes a "root" in the visual tree (no reachable parent)
  - parentFileUUID remains in metadata (historical record)
  - parentFilePath marked as stale
  - All history within the child is fully intact and usable
  - No data loss -- the child is self-contained
```

#### Scenario 4: Child file deleted

```
Detection:  Same as Scenario 2, but file is confirmed gone.
Resolution:
  - Child entry remains in parent's children array with an "unreachable" flag
  - Parent can be cleaned up via explicit user action:
    "Remove reference to deleted version 'draft-v3'?"
  - Automatic cleanup: if unreachable for > 90 days and user enables auto-cleanup,
    the reference is removed
```

#### Scenario 5: Circular reference (shouldn't happen, but defensive)

```
Detection:  During source chain traversal, if a UUID appears twice.
Resolution:
  - Break the cycle at the duplicate
  - Log warning
  - Display tree up to the cycle point
  - Do not crash or hang
```

**Source chain resolution pseudocode:**

```swift
enum ChainNodeStatus {
    case reachable(path: String)
    case movedTo(newPath: String)    // Found via registry at different path
    case unreachable                  // UUID exists in metadata but file not found
}

struct ResolvedChainNode {
    let uuid: UUID
    let displayName: String
    let status: ChainNodeStatus
    let forkTimestamp: Date?
    let snapshotIndex: Int?
}

func resolveSourceChain(for metadata: JNTMetadata,
                        registry: Registry) -> SourceTree {
    var visited = Set<UUID>()
    var tree = SourceTree()

    // Resolve parent chain (walk up)
    var currentParentUUID = metadata.sourceChain.parentFileUUID
    while let parentUUID = currentParentUUID, !visited.contains(parentUUID) {
        visited.insert(parentUUID)
        let node = resolveNode(uuid: parentUUID, registry: registry)
        tree.ancestors.append(node)

        if case .reachable(let path) = node.status,
           let parentMetadata = tryReadMetadata(at: path) {
            currentParentUUID = parentMetadata.sourceChain.parentFileUUID
        } else {
            break  // Chain broken -- stop traversal
        }
    }

    // Resolve children (walk down, breadth-first)
    for child in metadata.sourceChain.children {
        let node = resolveNode(uuid: child.childFileUUID, registry: registry)
        tree.children.append(node)
        // Deep traversal of grandchildren deferred to user request (lazy loading)
    }

    return tree
}

func resolveNode(uuid: UUID, registry: Registry) -> ResolvedChainNode {
    if let entry = registry.entries[uuid] {
        if FileManager.default.fileExists(atPath: entry.jntPath) {
            return ResolvedChainNode(
                uuid: uuid,
                displayName: entry.displayName,
                status: .reachable(path: entry.jntPath),
                forkTimestamp: nil,
                snapshotIndex: nil
            )
        } else {
            return ResolvedChainNode(
                uuid: uuid,
                displayName: entry.displayName,
                status: .unreachable,
                forkTimestamp: nil,
                snapshotIndex: nil
            )
        }
    }
    return ResolvedChainNode(
        uuid: uuid,
        displayName: "Unknown",
        status: .unreachable,
        forkTimestamp: nil,
        snapshotIndex: nil
    )
}
```

### 2.6 Cleanup System

**Three cleanup dimensions:**

#### By Capacity (total size of JettyNote folder)

```swift
struct CapacityCleanupPolicy: Codable {
    var enabled: Bool                   // Default: false
    var maxTotalSizeMB: Int             // Default: 500
    var targetSizeMB: Int               // Default: 400 (clean down to this)
    var protectRecentDays: Int          // Default: 7 (never clean files modified < 7 days ago)
}
```

Algorithm:
1. Compute total size of `~/Documents/JettyNote/`
2. If over `maxTotalSizeMB`, sort companion files by `lastModifiedAt` ascending
3. Delete oldest companions first (not user-created .jnt files -- those are the user's documents)
4. Stop when total size <= `targetSizeMB`
5. Never delete files modified within `protectRecentDays`
6. Update registry after cleanup

#### By Count (maximum number of companion files)

```swift
struct CountCleanupPolicy: Codable {
    var enabled: Bool                   // Default: false
    var maxCompanionCount: Int          // Default: 1000
    var targetCount: Int                // Default: 800
    var protectRecentDays: Int          // Default: 7
}
```

Same algorithm but counting files instead of bytes.

#### Single File History Cleanup

User can explicitly:
- Clear all snapshots for one document (keep current content, wipe history)
- Clear all snapshots older than N days for one document
- This operates within the .jnt file, rewriting it without the evicted snapshots

#### Nuclear Option: Clear All History

- Deletes everything in `~/Documents/JettyNote/companions/` and `orphans/`
- Resets `registry.json` to empty
- Does NOT touch user-created .jnt files stored elsewhere
- Requires explicit confirmation ("This will delete history for all external files. Your .jnt documents are not affected.")

**Orphan detection and cleanup:**

```swift
func detectOrphans(registry: Registry) -> [UUID] {
    var orphans: [UUID] = []
    for (uuid, entry) in registry.entries where entry.isCompanion {
        guard let originalPath = entry.companionOriginalPath else { continue }
        if !FileManager.default.fileExists(atPath: originalPath) {
            // Original file is gone -- this companion is an orphan
            orphans.append(uuid)
        }
    }
    return orphans
}

func handleOrphans(_ orphans: [UUID], registry: inout Registry, policy: OrphanPolicy) {
    switch policy {
    case .moveToOrphanFolder:
        // Move companion .jnt to ~/Documents/JettyNote/orphans/
        // User can review and delete manually
        for uuid in orphans {
            moveToOrphans(uuid: uuid, registry: &registry)
        }
    case .deleteAfterDays(let days):
        // If orphan has been in orphans/ for > N days, delete
        for uuid in orphans {
            if orphanAge(uuid) > days {
                deleteCompanion(uuid: uuid, registry: &registry)
            }
        }
    case .keepForever:
        // Do nothing -- orphans stay where they are
        break
    }
}
```

### 2.7 Data Structures (Swift)

```swift
// MARK: - Registry

struct Registry: Codable {
    var registryVersion: Int
    var lastScanAt: Date
    var entries: [UUID: RegistryEntry]
}

struct RegistryEntry: Codable {
    var jntPath: String
    var isCompanion: Bool
    var companionOriginalPath: String?
    var displayName: String
    var lastModifiedAt: Date
    var parentUUID: UUID?
    var childUUIDs: [UUID]
    var sizeBytes: Int
}

// MARK: - Document Model (in-memory, runtime)

class Document {
    // Identity
    let fileURL: URL
    var metadata: JNTMetadata

    // Content
    var currentContent: String
    var lastSavedContent: String

    // History
    var manifest: SnapshotManifest
    var loadedSnapshots: [Int: Snapshot]    // Lazy-loaded by index

    // Runtime state (not persisted)
    var isDirty: Bool { currentContent != lastSavedContent }
    var hasDownstreamGenerations: Bool {
        !metadata.sourceChain.children.isEmpty
    }
    var midTreeEditAcknowledged: Bool = false

    // Undo/Redo (in-memory only)
    var undoManager: UndoManager

    // Save trigger classification
    var saveTriggeredBy: SaveTrigger = .manual

    enum SaveTrigger {
        case manual          // Cmd+S
        case autoTimer       // 1-minute interval
        case focusLost       // Window/tab lost focus
        case tabClose        // Tab being closed
        case appTerminate    // App quitting

        func toSnapshotType() -> SnapshotType {
            switch self {
            case .manual: return .manualSave
            case .autoTimer, .focusLost: return .autoSave
            case .tabClose, .appTerminate: return .sessionBoundary
            }
        }
    }

    func nextSnapshotIndex() -> Int {
        return (manifest.newestIndex) + 1
    }

    func addSnapshot(_ snapshot: Snapshot) {
        loadedSnapshots[snapshot.snapshotIndex] = snapshot
        manifest.snapshots.append(SnapshotSummary(
            index: snapshot.snapshotIndex,
            timestamp: snapshot.timestamp,
            type: snapshot.snapshotType,
            bytesBefore: snapshot.bytesBefore
        ))
        manifest.snapshotCount += 1
        manifest.newestIndex = snapshot.snapshotIndex

        // Evict if over limit
        while manifest.snapshotCount > JNTFormat.maxSnapshots {
            evictOldestEligible()
        }
    }

    private func evictOldestEligible() {
        // Priority: autoSave adjacent < autoSave old < sessionBoundary old
        // Never evict: forkPoint, manualSave (unless > 80% of slots)
        guard let victim = findEvictionCandidate() else { return }
        mergeSnapshotWithNeighbor(index: victim)
    }

    private func findEvictionCandidate() -> Int? {
        let sortedSnapshots = manifest.snapshots.sorted { $0.index < $1.index }

        // Pass 1: adjacent autoSave within 2 minutes
        for i in 0..<(sortedSnapshots.count - 1) {
            let current = sortedSnapshots[i]
            let next = sortedSnapshots[i + 1]
            if current.type == .autoSave && next.type == .autoSave {
                let gap = next.timestamp.timeIntervalSince(current.timestamp)
                if gap < 120 { return current.index }
            }
        }

        // Pass 2: autoSave older than 7 days (keep one per hour)
        let sevenDaysAgo = Date().addingTimeInterval(-7 * 24 * 3600)
        var hourBuckets: [String: [SnapshotSummary]] = [:]
        for s in sortedSnapshots where s.type == .autoSave && s.timestamp < sevenDaysAgo {
            let hourKey = ISO8601DateFormatter().string(from: s.timestamp).prefix(13).description
            hourBuckets[hourKey, default: []].append(s)
        }
        for (_, bucket) in hourBuckets where bucket.count > 1 {
            return bucket.first?.index  // Evict oldest in over-populated hour
        }

        // Pass 3: autoSave older than 30 days (keep one per day)
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        var dayBuckets: [String: [SnapshotSummary]] = [:]
        for s in sortedSnapshots where s.type == .autoSave && s.timestamp < thirtyDaysAgo {
            let dayKey = ISO8601DateFormatter().string(from: s.timestamp).prefix(10).description
            dayBuckets[dayKey, default: []].append(s)
        }
        for (_, bucket) in dayBuckets where bucket.count > 1 {
            return bucket.first?.index
        }

        return nil  // Nothing eligible -- all slots used by important snapshots
    }

    private func mergeSnapshotWithNeighbor(index: Int) {
        // When evicting snapshot N:
        // Compose diff(N) with diff(N+1) to create a combined diff
        // that goes directly from version N+1's newer state to version N-1's state
        // Remove snapshot N from manifest and loaded snapshots
        guard let victim = loadedSnapshots[index] else { return }

        // Find the next-older snapshot
        let sorted = manifest.snapshots.sorted { $0.index < $1.index }
        guard let victimPos = sorted.firstIndex(where: { $0.index == index }),
              victimPos > 0 else {
            // Oldest snapshot -- just remove it (lose that history point)
            manifest.snapshots.removeAll { $0.index == index }
            manifest.snapshotCount -= 1
            loadedSnapshots.removeValue(forKey: index)
            return
        }

        let olderIndex = sorted[victimPos - 1].index
        if let olderSnapshot = loadedSnapshots[olderIndex] {
            // Compose: olderSnapshot.ops should now go from victim's "after" state
            // directly to olderSnapshot's reconstructed state
            // This is: apply victim's diff, then apply olderSnapshot's diff
            // Composed into a single diff sequence
            let composed = composeDiffs(newer: victim.ops, older: olderSnapshot.ops)
            loadedSnapshots[olderIndex] = Snapshot(
                snapshotIndex: olderIndex,
                timestamp: olderSnapshot.timestamp,
                snapshotType: olderSnapshot.snapshotType,
                editSummary: olderSnapshot.editSummary,
                bytesBefore: olderSnapshot.bytesBefore,
                bytesAfter: victim.bytesAfter,
                ops: composed
            )
        }

        manifest.snapshots.removeAll { $0.index == index }
        manifest.snapshotCount -= 1
        loadedSnapshots.removeValue(forKey: index)
    }
}

// MARK: - Source Tree (for UI display)

struct SourceTree {
    var ancestors: [ResolvedChainNode] = []    // Ordered: direct parent first, grandparent next
    var currentFile: ResolvedChainNode?
    var children: [ResolvedChainNode] = []     // Direct children only (lazy-load deeper)
}

// MARK: - Cleanup Policies

struct CleanupSettings: Codable {
    var capacityPolicy: CapacityCleanupPolicy
    var countPolicy: CountCleanupPolicy
    var orphanPolicy: OrphanPolicySetting
    var autoCleanupEnabled: Bool              // Master switch
    var autoCleanupIntervalHours: Int         // Default: 168 (weekly)
}

struct CapacityCleanupPolicy: Codable {
    var enabled: Bool
    var maxTotalSizeMB: Int
    var targetSizeMB: Int
    var protectRecentDays: Int
}

struct CountCleanupPolicy: Codable {
    var enabled: Bool
    var maxCompanionCount: Int
    var targetCount: Int
    var protectRecentDays: Int
}

enum OrphanPolicySetting: String, Codable {
    case moveToOrphanFolder
    case deleteAfter90Days
    case keepForever
}

// MARK: - File I/O

/// Atomic write pattern for .jnt bundles
func atomicWriteJNT(_ document: Document) throws {
    let tempURL = document.fileURL
        .deletingPathExtension()
        .appendingPathExtension("jnt.tmp")

    // Build ZIP archive in memory or to temp file
    try writeJNTBundle(
        to: tempURL,
        content: document.currentContent,
        metadata: document.metadata,
        manifest: document.manifest,
        snapshots: document.loadedSnapshots
    )

    // Atomic replace
    _ = try FileManager.default.replaceItemAt(
        document.fileURL,
        withItemAt: tempURL
    )
}

/// Companion path derivation
func companionJNTPath(for originalPath: URL) -> URL {
    // Given a UUID, compute the companion storage path
    // Called during Save As for external files
    let uuid = UUID()  // Generated earlier in the Save As flow
    let prefix = String(uuid.uuidString.prefix(2).lowercased())
    let jettyNoteDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("JettyNote")
        .appendingPathComponent("companions")
        .appendingPathComponent(prefix)
    try? FileManager.default.createDirectory(at: jettyNoteDir, withIntermediateDirectories: true)
    return jettyNoteDir.appendingPathComponent("\(uuid.uuidString).jnt")
}
```

---

## Cross-System Integration

### How Save triggers History Layer updates

```
User action          -> Save System (System 2)    -> File Format (System 1)
-----------             ----------------------       ----------------------
Cmd+S                   save()                       Write content.txt
                                                     Create snapshot .rdiff
                                                     Update manifest.json
                                                     Update metadata.json
                                                     Update Preview.txt

Save As...              saveAs()                     Write NEW .jnt bundle
                                                     Update PARENT .jnt bundle
                                                     Update registry.json

Auto-save timer         save() w/ autoSave trigger   Same as Cmd+S but
                                                     snapshotType = autoSave

Tab close               save() w/ tabClose trigger   Same as Cmd+S but
                                                     snapshotType = sessionBoundary
```

### How Branch Detection reads from File Format

```
Document opens -> Read metadata.json -> Check sourceChain.children
                                     -> If non-empty, set hasDownstream flag
                                     -> On first edit, show branch warning

Source chain UI -> Read metadata.json -> Resolve parent UUID via registry
               -> Walk parent chain  -> Read each parent's metadata.json
               -> Build SourceTree   -> Display ancestor + children tree
```

### External File Lifecycle

```
1. User opens /Desktop/report.txt
   -> Tab shows blue (external file indicator)
   -> No companion .jnt exists yet

2. User edits and presses Cmd+S
   -> report.txt saved to /Desktop/report.txt (original format)
   -> Companion created: ~/Documents/JettyNote/companions/XX/<UUID>.jnt
   -> Companion metadata.companionOf = { originalPath: "/Desktop/report.txt", originalFormat: "txt" }
   -> Registry updated with new entry
   -> Tab stays blue (still an external file with companion)

3. User continues editing, auto-save fires
   -> report.txt updated
   -> Companion .jnt updated (new snapshot added)

4. User does Save As -> /Desktop/report-v2.txt
   -> report-v2.txt created
   -> NEW companion .jnt created for report-v2.txt
   -> Original companion .jnt gets child reference added
   -> New companion .jnt gets parent reference to original companion
   -> Active document switches to report-v2.txt

5. User deletes /Desktop/report.txt from Finder
   -> Next app launch: orphan detection finds companion without original
   -> Companion moved to ~/Documents/JettyNote/orphans/
   -> After 90 days (if policy set): deleted
```

---

## Edge Cases & Failure Modes

### 1. Crash during atomic write

**Scenario:** App crashes between writing temp file and renaming.
**Result:** Temp file `.jnt.tmp` exists alongside original `.jnt`.
**Recovery:** On next launch, if `.jnt.tmp` exists and is newer than `.jnt`, offer to recover from it. If `.jnt.tmp` is corrupt, discard it and use `.jnt`.

### 2. Disk full during save

**Scenario:** DEFLATE write fails partway through.
**Result:** Temp file is incomplete.
**Recovery:** Delete incomplete temp file. Alert user. Original `.jnt` is untouched (atomic write ensures this).

### 3. Two instances editing same file

**Scenario:** User opens same `.jnt` in two windows (should be prevented by tab management, but edge case).
**Result:** Last writer wins. No ACID guarantees across processes.
**Mitigation:** Use file coordination (`NSFileCoordinator`) for `.jnt` files. Second instance gets read-only access or a warning.

### 4. Very large paste (10MB text pasted into 1KB document)

**Scenario:** Diff between versions is essentially the entire new content.
**Result:** Single snapshot could be 10MB+.
**Mitigation:** If a single diff exceeds 1MB, store it as a "full snapshot" (complete content at that point) instead of a diff. This breaks the diff chain but caps the storage cost. Mark it with a special flag in the manifest.

### 5. Format version mismatch

**Scenario:** User opens a `.jnt` created by a newer version of the app.
**Result:** `formatVersion` > current app's known version.
**Mitigation:**
- If major version differs (e.g., 2 vs 1): warn user, attempt best-effort read of `content.txt` only.
- If minor version differs (e.g., 1.1 vs 1.0): read normally, ignore unknown fields in JSON.
- Current spec uses integer versioning. Switch to semver if needed in future.

### 6. Unicode edge cases

**Scenario:** Content contains combining characters, zero-width joiners, or mixed bidi text.
**Result:** Line-level diffing works correctly because it operates on string lines, not grapheme clusters.
**Mitigation:** Normalize to NFC on save. Store normalized form. Display original form (macOS handles this).

### 7. Save As to the same path (overwrite self)

**Scenario:** User does Save As and picks the exact same file path.
**Result:** This should behave as a normal Save, not create a new generation.
**Mitigation:** Detect same-path Save As and redirect to Save flow. No new UUID, no parent-child link.

### 8. Circular Save As chain

**Scenario:** File A -> Save As -> B -> Save As -> C -> Save As -> overwrite A.
**Result:** A's UUID is replaced by C's Save As result. The original A is gone.
**Mitigation:** Save As to an existing `.jnt` path should warn: "This will replace the existing document and its history. Continue?" If confirmed, the old file's UUID is lost. The new file gets a fresh UUID with parent = C.
