# JettyNotepad Phase 1-3 Implementation — Long-Running Agent Prompt

> **Scope:** Phase 1 (MVP) + Phase 2 (History) + Phase 3 (External & Branch)
> **Estimated time:** 3 sessions (~8-12h each), each phase independently verifiable
> **Budget:** est 30h + 20% buffer = 36h total
> **Phase 4-5:** Deferred to `TODO.md`

---

## Reference: Project State

### Directory

```
/Users/vox/JNPT/
├── docs/
│   ├── ARCHITECTURE.md                    # Full architecture (read this first)
│   ├── jnt-format-and-branch-system-spec.md
│   ├── competitive-research.md
│   ├── JettyNotepad_PRD_v1.0.docx
│   └── JettyNotepad_Branch_Save_System_Spec_v1.0.docx
├── TODO.md                                # Phase 4-5 deferred work
└── AGENT_PROMPT_v1.1.0.md                 # This file
```

No code exists yet. Building from scratch.

### Tech Stack (Final — Do Not Change)

| Component | Choice | Note |
|-----------|--------|------|
| Language | Swift 5.9+ | macOS native |
| UI Framework | **AppKit** | SwiftUI only for Preferences via NSHostingView |
| Editor | NSTextView + TextKit 1 | Phase 1-2 plain text; Phase 4 adds Markdown |
| Storage | **SQLite** (.jnt = SQLite DB) | WAL mode, atomic writes |
| Diff | **diff-match-patch** | **Clean-room Swift implementation (~500 lines)** |
| Tab coloring | **Custom tab bar view** | Not NSTabbedWindow native tinting (non-public API) |
| Deploy target | macOS 13 (Ventura)+ | |

### SQLite Schema (.jnt)

```sql
CREATE TABLE document (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    content TEXT NOT NULL,
    cursor_position INTEGER DEFAULT 0,
    scroll_position REAL DEFAULT 0.0,
    created_at TEXT NOT NULL,                 -- ISO 8601
    modified_at TEXT NOT NULL,                -- ISO 8601
    original_line_ending TEXT DEFAULT 'LF'
);

CREATE TABLE snapshots (
    seq INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    snapshot_type TEXT NOT NULL,              -- manualSave/autoSave/sessionBoundary/forkPoint
    edit_summary TEXT,                        -- type/paste/delete/replace/mixed
    diff_data BLOB NOT NULL,                 -- diff-match-patch compressed reverse diff
    content_length_before INTEGER,
    content_length_after INTEGER
);

CREATE TABLE metadata (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE children (
    child_uuid TEXT PRIMARY KEY,
    child_path TEXT,
    fork_timestamp TEXT NOT NULL,
    fork_snapshot_seq INTEGER
);

CREATE TRIGGER limit_snapshots AFTER INSERT ON snapshots
BEGIN
    DELETE FROM snapshots
    WHERE seq IN (
        SELECT seq FROM snapshots ORDER BY seq ASC
        LIMIT max(0, (SELECT count(*) FROM snapshots) - 100)
    );
END;
```

### Metadata Keys

| key | example |
|-----|---------|
| `format_version` | `"1"` |
| `file_uuid` | UUID string |
| `display_name` | Auto from first line |
| `display_name_source` | `"firstLine"` / `"userSet"` |
| `parent_uuid` | UUID or absent |
| `parent_path` | Last known parent path |
| `parent_snapshot_seq` | Fork point in parent |
| `parent_fork_timestamp` | ISO 8601 |
| `companion_original_path` | For external file companions |
| `companion_original_format` | `"txt"` / `"md"` |

### App Identity

- **Bundle ID:** `com.jettymarquis.jettynotepad`
- **UTI:** `com.jettymarquis.jettynotepad.jnt`
- **GitHub:** jettymarquis

---

## Critical Rules

1. **AppKit for main UI.** SwiftUI ONLY via `NSHostingView` for Preferences.
2. **NSDocument subclass** is the document model. No custom lifecycle.
3. **SQLite = .jnt.** Use sqlite3 C API via Swift bridging. No Core Data. No GRDB.
4. **diff-match-patch clean-room implementation.** ~500 lines Swift. Do NOT use third-party packages.
5. **Reverse diff chain.** Current content in full; older versions reconstructed backward.
6. **100 snapshot limit.** SQLite trigger enforces. Smart eviction when full.
7. **Save ≠ new generation.** Only Save As creates parent-child links.
8. **Undo persists across saves.** Save does NOT clear undo stack.
9. **Tab coloring via custom view.** Do not hack NSTabbedWindow private API.
10. **macOS 13+ only.** No APIs from 14+.
11. **Minimize dependencies.** SPM only. System frameworks preferred. Zero third-party in Phase 1.
12. **XCTest for all core logic.**

---

## Phase 1: Basic Editor MVP

**Goal:** Working macOS app — open, edit, save .jnt files with tabs, auto-save, session restore.
**Time:** ~8-12h

### 1.1 Initialize Project

```bash
cd /Users/vox/JNPT
git init
cat > .gitignore << 'EOF'
.DS_Store
*.xcuserstate
build/
DerivedData/
.build/
EOF
```

Create Xcode project (macOS App, Swift, AppKit, Document-based):

```
JettyNotepad/
├── JettyNotepad.xcodeproj/
├── JettyNotepad/
│   ├── App/
│   │   ├── AppDelegate.swift
│   │   ├── main.swift                       # or @main on AppDelegate
│   │   └── Info.plist
│   ├── Document/
│   │   ├── JNTDocument.swift                # NSDocument subclass
│   │   └── JNTDocumentController.swift
│   ├── Editor/
│   │   └── EditorViewController.swift       # NSViewController + NSTextView
│   ├── Storage/
│   │   ├── SQLiteDatabase.swift             # Thin C API wrapper
│   │   ├── JNTFileStore.swift               # .jnt read/write
│   │   └── JNTSchema.swift                  # CREATE TABLE + migration
│   ├── Window/
│   │   ├── JNTWindowController.swift        # NSWindowController + tabs
│   │   └── TabStateManager.swift            # Tab color tracking
│   ├── AutoSave/
│   │   └── AutoSaveManager.swift
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   └── MainMenu.xib                     # Or build menu programmatically
│   └── JettyNotepad.entitlements
└── JettyNotepadTests/
    ├── SQLiteDatabaseTests.swift
    ├── JNTFileStoreTests.swift
    └── JNTSchemaTests.swift
```

Create `CLAUDE.md`:
```markdown
# JettyNotepad

macOS native text editor with built-in version history and branch tracking.

## Tech Stack
- Swift + AppKit (NOT SwiftUI for main UI)
- SQLite for .jnt file format (WAL mode)
- diff-match-patch (clean-room Swift, ~500 lines)
- Deployment target: macOS 13+

## Build
cd /Users/vox/JNPT/JettyNotepad
xcodebuild -scheme JettyNotepad -configuration Debug build

## Test
xcodebuild -scheme JettyNotepad -configuration Debug test

## Architecture
See docs/ARCHITECTURE.md
```

**Verification 1.1:**
```bash
cd /Users/vox/JNPT/JettyNotepad && xcodebuild -scheme JettyNotepad -configuration Debug build 2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED)"
# Must output: BUILD SUCCEEDED
```

### 1.2 SQLite Wrapper

File: `Storage/SQLiteDatabase.swift`

Thin wrapper over C `sqlite3` API:

```swift
import Foundation
import SQLite3

class SQLiteDatabase {
    private var db: OpaquePointer?

    init(path: String) throws
    deinit { close() }

    func execute(_ sql: String) throws
    func executeWithParams(_ sql: String, params: [SQLiteValue]) throws
    func query(_ sql: String, params: [SQLiteValue]) throws -> [[String: SQLiteValue]]
    func insertReturningRowId(_ sql: String, params: [SQLiteValue]) throws -> Int64
    func beginTransaction() throws
    func commitTransaction() throws
    func rollbackTransaction() throws
    func close()
}

enum SQLiteValue {
    case text(String)
    case int(Int64)
    case double(Double)
    case blob(Data)
    case null
}
```

On open, always execute:
```sql
PRAGMA journal_mode=WAL;
PRAGMA foreign_keys=ON;
```

**Verification 1.2:**
```bash
# Unit test: create in-memory DB, create table, insert, query, verify round-trip
xcodebuild -scheme JettyNotepad -configuration Debug test -only-testing:JettyNotepadTests/SQLiteDatabaseTests 2>&1 | grep -E "(Test Suite|passed|failed)"
# Must: all passed, 0 failed
```

### 1.3 Schema & JNTFileStore

File: `Storage/JNTSchema.swift` — all CREATE TABLE statements + `migrate(db:)` using `PRAGMA user_version`.

File: `Storage/JNTFileStore.swift`:

```swift
class JNTFileStore {
    private let db: SQLiteDatabase
    let url: URL

    init(url: URL) throws                    // Open existing
    static func create(at url: URL, content: String, uuid: UUID) throws -> JNTFileStore

    // Document CRUD
    func readContent() throws -> String
    func readDocumentState() throws -> JNTDocumentState
    func saveContent(_ content: String, cursor: Int, scroll: Double) throws
    func updateModifiedAt() throws

    // Metadata
    func readMetadata() throws -> [String: String]
    func readMetadata(key: String) throws -> String?
    func writeMetadata(key: String, value: String) throws

    // Snapshots (Phase 2 will extend)
    func insertSnapshot(type: String, editSummary: String?, diffData: Data,
                        lengthBefore: Int, lengthAfter: Int) throws -> Int64
    func readSnapshotManifest() throws -> [SnapshotSummary]
    func readSnapshotDiff(seq: Int) throws -> Data
    func snapshotCount() throws -> Int

    // Children (Phase 3 will extend)
    func addChild(uuid: UUID, path: String, forkTimestamp: Date, forkSeq: Int) throws
    func readChildren() throws -> [ChildRecord]

    func close()
}
```

**Verification 1.3:**
```bash
xcodebuild -scheme JettyNotepad -configuration Debug test -only-testing:JettyNotepadTests/JNTFileStoreTests 2>&1 | grep -E "(passed|failed)"
# Tests: create .jnt → open → read content matches → write metadata → read back → round-trip OK
# Also: sqlite3 /tmp/test.jnt "PRAGMA journal_mode;" must return "wal"
```

### 1.4 JNTDocument

File: `Document/JNTDocument.swift` — `NSDocument` subclass.

```swift
class JNTDocument: NSDocument {
    var fileStore: JNTFileStore?
    var content: String = ""
    var lastSavedContent: String = ""
    var fileUUID: UUID = UUID()

    override class var autosavesInPlace: Bool { true }
    override class var autosavesDrafts: Bool { true }

    override func makeWindowControllers()        // → JNTWindowController
    override func read(from url: URL, ofType typeName: String) throws  // Open SQLite
    override func write(to url: URL, ofType typeName: String) throws   // Save SQLite
    override func save(to url: URL, ofType typeName: String,
                       for saveOperation: NSDocument.SaveOperationType,
                       completionHandler: @escaping (Error?) -> Void)  // Save As hook

    // Session restore
    override func encodeRestorableState(with coder: NSCoder)
    override func restoreState(with coder: NSCoder)
}
```

Key:
- `read` → `JNTFileStore(url:)` → `readDocumentState()` → populate `content`
- `write` → `fileStore.saveContent(content, ...)` — Phase 2 adds snapshot creation here
- New documents: generate UUID in `init()`, create .jnt on first save

### 1.5 Editor View Controller

File: `Editor/EditorViewController.swift`

```swift
class EditorViewController: NSViewController, NSTextViewDelegate {
    var textView: NSTextView!
    weak var document: JNTDocument?

    override func loadView() {
        let scrollView = NSScrollView()
        textView = NSTextView()
        // Config:
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.allowsUndo = true
        textView.undoManager?.levelsOfUndo = 100
        textView.isAutomaticSpellingCorrectionEnabled = false  // Phase 4
        textView.delegate = self
        scrollView.documentView = textView
        self.view = scrollView
    }

    func textDidChange(_ notification: Notification) {
        document?.content = textView.string
        document?.updateChangeCount(.changeDone)
    }
}
```

### 1.6 Window Controller + Tabs

File: `Window/JNTWindowController.swift`

```swift
class JNTWindowController: NSWindowController {
    override func windowDidLoad() {
        super.windowDidLoad()
        window?.tabbingMode = .preferred
        window?.setFrameAutosaveName("JettyNotepadMainWindow")
    }
}
```

`tabbingMode = .preferred` gives native tab bar, drag-out, merge — for free.

### 1.7 Tab State Colors (Custom View Approach)

File: `Window/TabStateManager.swift`

Since we cannot tint NSTabbedWindow tabs via public API, use a **colored dot indicator** in the window title or a thin colored stripe below the tab bar:

```swift
enum TabState {
    case saved, modified, external

    var color: NSColor {
        switch self {
        case .saved:    return NSColor.systemGreen.withAlphaComponent(0.6)
        case .modified: return NSColor.systemYellow.withAlphaComponent(0.6)
        case .external: return NSColor.systemBlue.withAlphaComponent(0.6)
        }
    }

    var symbol: String {
        switch self {
        case .saved:    return ""       // No indicator
        case .modified: return " \u{25CF}"  // Filled circle ●
        case .external: return " \u{25CB}"  // Open circle ○
        }
    }
}
```

Append the symbol to the window/tab title: `"Meeting notes ●"` for modified.
Phase 1: implement saved/modified only. Phase 3 adds external.

### 1.8 Auto-Save Manager

File: `AutoSave/AutoSaveManager.swift`

Primary mechanism: `NSDocument.autosavesInPlace = true` (system auto-save).

Layer custom behaviors:

```swift
class AutoSaveManager {
    weak var document: JNTDocument?
    private var timer: Timer?
    private var idleTimer: Timer?
    private var lastEditTime: Date?

    func start(interval: TimeInterval = 60) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.triggerAutoSave()
        }
    }

    func stop() { timer?.invalidate(); idleTimer?.invalidate() }

    func documentDidLoseFocus() { triggerAutoSave() }

    func documentContentDidChange() {
        lastEditTime = Date()
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.triggerAutoSave()  // Idle for 5s after edits
        }
    }

    private func triggerAutoSave() {
        guard let doc = document, doc.content != doc.lastSavedContent else { return }
        doc.autosave(withImplicitCancellability: false) { _ in }
    }
}
```

### 1.9 AppDelegate + Info.plist

File: `App/AppDelegate.swift` — register document types, handle untitled file on launch.

`Info.plist` must declare:
- `CFBundleDocumentTypes`: `.jnt` as Editor role
- `UTExportedTypeDeclarations`: `com.jettymarquis.jettynotepad.jnt` conforming to `public.data`, `public.content`
- `NSSupportsAutomaticTermination: true`
- `NSSupportsSuddenTermination: false`

### 1.10 Menu Bar

Build standard menus (xib or programmatic):
- **File:** New (Cmd+N), Open (Cmd+O), Save (Cmd+S), Save As (Cmd+Shift+S), Close (Cmd+W), Print (Cmd+P)
- **Edit:** Undo (Cmd+Z), Redo (Cmd+Shift+Z), Cut/Copy/Paste/Select All, Find (Cmd+F)
- **View:** (empty in Phase 1, History added in Phase 2)
- **Window:** standard macOS window menu
- **Help:** standard

### 1.11 Session Restoration

Implement `NSWindowRestoration` on `JNTWindowController`:

```swift
override func encodeRestorableState(with coder: NSCoder, backgroundQueue queue: OperationQueue) {
    super.encodeRestorableState(with: coder, backgroundQueue: queue)
}

static func restoreWindow(withIdentifier identifier: NSUserInterfaceItemIdentifier,
                           state: NSCoder,
                           completionHandler: @escaping (NSWindow?, Error?) -> Void) {
    // Restore from state
}
```

In `JNTDocument`:
```swift
override func encodeRestorableState(with coder: NSCoder) {
    super.encodeRestorableState(with: coder)
    coder.encode(content, forKey: "jnt.unsavedContent")
    coder.encode(editorVC?.textView.selectedRange().location ?? 0, forKey: "jnt.cursorPos")
}
```

### Phase 1 Gate

```bash
# G1: Build
cd /Users/vox/JNPT/JettyNotepad && xcodebuild -scheme JettyNotepad -configuration Debug build 2>&1 | grep "BUILD SUCCEEDED"

# G2: Tests
xcodebuild -scheme JettyNotepad -configuration Debug test 2>&1 | grep -E "Test Suite .* passed"

# G3: .jnt is valid SQLite with correct schema
JNT=/tmp/jnpt_gate1.jnt
sqlite3 "$JNT" "SELECT count(*) FROM document;" 2>/dev/null && \
sqlite3 "$JNT" "SELECT count(*) FROM metadata WHERE key='format_version';" 2>/dev/null && \
sqlite3 "$JNT" "PRAGMA journal_mode;" 2>/dev/null | grep -q "wal" && \
echo "GATE 1 PASSED" || echo "GATE 1 FAILED"

# G4: Commit
cd /Users/vox/JNPT && git log --oneline -1
# Must exist
```

**Required unit tests:**
- `SQLiteDatabaseTests`: open, WAL mode, create table, insert, query, transaction rollback
- `JNTFileStoreTests`: create .jnt, open, content round-trip, metadata round-trip
- `JNTSchemaTests`: migration from version 0→1, idempotent re-migration

**DO NOT proceed to Phase 2 until all G1-G4 pass.**

---

## Phase 2: History & Tracing

**Goal:** Snapshot system (diff-match-patch), history browsing UI, Save As generation tracking, tab colors live.
**Time:** ~8-12h
**Prerequisite:** Phase 1 Gate passes.

### 2.1 diff-match-patch Clean-Room Implementation

Create new directory and files:

```
JettyNotepad/DiffMatchPatch/
├── DiffMatchPatch.swift       # Main class (~300 lines)
├── Diff.swift                 # Diff computation
└── Patch.swift                # Patch create/apply/serialize
```

Implement based on the published algorithm (Neil Fraser's paper + reference pseudocode at https://github.com/google/diff-match-patch/wiki/Algorithm):

**Required public API (minimum for Phase 2):**

```swift
struct Diff {
    enum Operation { case insert, delete, equal }
    let operation: Operation
    let text: String
}

struct Patch {
    var diffs: [Diff]
    var start1: Int
    var start2: Int
    var length1: Int
    var length2: Int
}

class DiffMatchPatch {
    /// Compute diffs between two strings
    func diffMain(text1: String, text2: String) -> [Diff]

    /// Semantic cleanup — merge adjacent edits for human readability
    func diffCleanupSemantic(_ diffs: inout [Diff])

    /// Create patches from two strings
    func patchMake(text1: String, text2: String) -> [Patch]

    /// Apply patches to text. Returns (resultText, successArray).
    func patchApply(patches: [Patch], text: String) -> (String, [Bool])

    /// Serialize patches to portable text format
    func patchToText(patches: [Patch]) -> String

    /// Deserialize patches from text
    func patchFromText(_ text: String) throws -> [Patch]
}
```

Implementation notes:
- Start with the "diff_bisect" approach (Myers O(ND)) for `diffMain`
- Add `diffCleanupSemantic` to merge small edits into meaningful chunks
- Patch format: use the standard diff-match-patch text format for `patchToText`/`patchFromText` — this ensures debuggability via `sqlite3` inspection of diff_data
- Character-level diffs, NOT line-level
- Handle Unicode correctly (Swift `String` is already Unicode-native)

**Verification 2.1:**
```bash
xcodebuild -scheme JettyNotepad -configuration Debug test -only-testing:JettyNotepadTests/DiffMatchPatchTests 2>&1 | grep -E "(passed|failed)"
```

**Required tests:**
- Empty strings, identical strings, completely different strings
- Single character change, word insertion, paragraph deletion
- Unicode: Chinese text diffs, emoji diffs
- Patch round-trip: text1 → patches → apply to text1 → get text2
- Patch serialization round-trip: patches → text → parse → identical patches
- Large text (50KB) diff in < 100ms

### 2.2 Snapshot Manager

File: `JettyNotepad/Snapshot/SnapshotManager.swift`

```swift
class SnapshotManager {
    let fileStore: JNTFileStore
    let dmp = DiffMatchPatch()

    /// Create snapshot (reverse diff from current → previous)
    func createSnapshot(previousContent: String, currentContent: String,
                        type: String, editSummary: String?) throws -> Int64 {
        // 1. Compute reverse patches: applying to currentContent yields previousContent
        let patches = dmp.patchMake(text1: currentContent, text2: previousContent)
        let patchText = dmp.patchToText(patches: patches)
        let compressed = try (patchText.data(using: .utf8)! as NSData)
            .compressed(using: .zlib) as Data

        // 2. INSERT into snapshots
        return try fileStore.insertSnapshot(
            type: type, editSummary: editSummary, diffData: compressed,
            lengthBefore: previousContent.utf8.count,
            lengthAfter: currentContent.utf8.count
        )
    }

    /// Reconstruct content at snapshot `seq`
    func reconstructContent(at targetSeq: Int, currentContent: String) throws -> String {
        let manifest = try fileStore.readSnapshotManifest()
        var result = currentContent

        // Apply diffs from newest to target (descending seq order)
        for summary in manifest.reversed() {
            guard summary.seq >= targetSeq else { break }
            let compressed = try fileStore.readSnapshotDiff(seq: summary.seq)
            let decompressed = try (compressed as NSData).decompressed(using: .zlib) as Data
            let patchText = String(data: decompressed, encoding: .utf8)!
            let patches = try dmp.patchFromText(patchText)
            let (applied, _) = dmp.patchApply(patches: patches, text: result)
            result = applied
        }
        return result
    }

    /// Smart eviction when count > 100
    func evictIfNeeded() throws {
        // Priority: merge adjacent autoSaves within 2min → thin >7day autoSaves → thin >30day
        // Never evict: manualSave, forkPoint
        // Compose diffs when evicting intermediate snapshot
    }
}
```

### 2.3 Integrate Snapshots into Save

Modify `JNTDocument.write(to:ofType:)`:

```swift
override func write(to url: URL, ofType typeName: String) throws {
    guard let store = fileStore else { throw JNTError.noFileStore }

    if content != lastSavedContent {
        let snapshotType = currentSaveIsManual ? "manualSave" : "autoSave"
        try snapshotManager.createSnapshot(
            previousContent: lastSavedContent,
            currentContent: content,
            type: snapshotType,
            editSummary: nil
        )
        try snapshotManager.evictIfNeeded()
    }

    try store.saveContent(content, cursor: currentCursorPosition, scroll: currentScrollPosition)
    lastSavedContent = content
}
```

### 2.4 History Browsing UI

File: `JettyNotepad/History/HistoryPanelController.swift`

Accessible via **View > History** (Cmd+Shift+H) or toolbar button.

Layout: `NSSplitViewController` — left: timeline list, right: snapshot preview + diff.

**Timeline (left):**
- `NSTableView` with rows: timestamp, snapshot type icon, content size
- Newest at top
- Clicking a row reconstructs content at that snapshot

**Preview (right):**
- Read-only `NSTextView` showing reconstructed content
- Toggle: "Content" vs "Diff" view
- Diff view: colored inline diff (green = added in current, red = removed from current)

**"Branch From Here" button:** visible when viewing a snapshot — triggers Save As with content reconstructed at that snapshot, `parentSnapshotSeq` set to that seq.

### 2.5 Save As with Generation Tracking

Extend `JNTDocument.save(to:ofType:for:completionHandler:)`:

When `saveOperation == .saveAsOperation`:

1. Create `forkPoint` snapshot in **parent** file
2. Generate new UUID for child
3. Insert child record in parent's `children` table
4. Commit parent .jnt
5. Create new .jnt at target path:
   - `document`: current content
   - `snapshots`: single `forkPoint` entry (empty diff, seq 0)
   - `metadata`: new UUID + `parent_uuid` + `parent_path` + `parent_snapshot_seq`
   - `children`: empty
6. Switch active document to child file
7. Update `lastSavedContent`

### 2.6 Tab Colors Live

Wire up `TabStateManager` to respond to document state changes:

- `NSDocument.updateChangeCount(.changeDone)` → title becomes `"name ●"` (modified/yellow)
- After successful save → title becomes `"name"` (saved/green, no indicator)
- Phase 3 will add `"name ○"` for external files

Use `NSWindow.title` manipulation — simplest reliable approach.

### Phase 2 Gate

```bash
# G1: Build
cd /Users/vox/JNPT/JettyNotepad && xcodebuild -scheme JettyNotepad -configuration Debug build 2>&1 | grep "BUILD SUCCEEDED"

# G2: All tests pass (Phase 1 + Phase 2)
xcodebuild -scheme JettyNotepad -configuration Debug test 2>&1 | grep -E "Test Suite .* passed"

# G3: Snapshot round-trip integrity
# (Part of DiffMatchPatchTests + SnapshotManagerTests)
# text1 → save → edit to text2 → save → reconstruct seq 1 → must equal text1

# G4: Save As creates parent-child link
JNT_PARENT=/tmp/jnpt_parent.jnt
JNT_CHILD=/tmp/jnpt_child.jnt
sqlite3 "$JNT_PARENT" "SELECT count(*) FROM children;" | grep -q "1" && \
sqlite3 "$JNT_CHILD" "SELECT value FROM metadata WHERE key='parent_uuid';" | grep -q "[0-9a-f]" && \
echo "GATE 2 PASSED" || echo "GATE 2 FAILED"

# G5: Commit
cd /Users/vox/JNPT && git log --oneline | head -5
```

**Required unit tests:**
- `DiffMatchPatchTests`: see 2.1 above (6+ test cases)
- `SnapshotManagerTests`: create, reconstruct, eviction, compose diffs
- `SaveAsTests`: parent-child link, forkPoint snapshot, UUID generation

**DO NOT proceed to Phase 3 until all G1-G5 pass.**

---

## Phase 3: External Files & Branching

**Goal:** Dual-format save for .txt/.md, full source chain, branch tree visualization, mid-tree warnings, history folder management.
**Time:** ~8-12h
**Prerequisite:** Phase 2 Gate passes.

### 3.1 External File Manager

New files:

```
JettyNotepad/External/
├── ExternalFileManager.swift       # Companion .jnt creation/management
├── RegistryManager.swift           # UUID→path index (registry.json)
└── CleanupManager.swift            # Orphan scan, capacity/count cleanup
```

**ExternalFileManager:**

```swift
class ExternalFileManager {
    static let jettyNoteFolder: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            .appendingPathComponent("JettyNote")
    }()

    static func companionURL(for uuid: UUID) -> URL {
        let prefix = String(uuid.uuidString.prefix(2).lowercased())
        return jettyNoteFolder
            .appending(components: "companions", prefix, "\(uuid.uuidString).jnt")
    }

    static func ensureFolderStructure() throws {
        let fm = FileManager.default
        for sub in ["companions", "orphans"] {
            try fm.createDirectory(at: jettyNoteFolder.appending(component: sub),
                                   withIntermediateDirectories: true)
        }
    }
}
```

### 3.2 Register External File Types

Update `Info.plist` — add `.txt` and `.md` as Editor role document types:
- `public.plain-text`
- `net.daringfireball.markdown`

### 3.3 Modify JNTDocument for External Files

Add to `JNTDocument`:

```swift
var isExternalFile = false
var externalFileURL: URL?
var companionUUID: UUID?
```

In `read(from:ofType:)`:
- If type is `.jnt` → read SQLite (existing path)
- If type is `.txt`/`.md` → read plain text, set `isExternalFile = true`, assign or lookup `companionUUID`, update tab indicator to `"name ○"`

In `write(to:ofType:)`:
- If `isExternalFile`:
  1. Write original format to `externalFileURL`
  2. Write/update companion .jnt at `ExternalFileManager.companionURL(for: companionUUID!)`
  3. Create snapshot in companion .jnt

### 3.4 Registry Manager

File: `External/RegistryManager.swift`

```swift
struct RegistryEntry: Codable {
    var jntPath: String
    var isCompanion: Bool
    var companionOriginalPath: String?
    var displayName: String
    var lastModifiedAt: String
    var parentUUID: String?
    var childUUIDs: [String]
    var sizeBytes: Int64
}

class RegistryManager {
    static let registryURL = ExternalFileManager.jettyNoteFolder.appending(component: "registry.json")

    static func load() throws -> [String: RegistryEntry]   // UUID → entry
    static func save(_ entries: [String: RegistryEntry]) throws
    static func upsert(uuid: UUID, entry: RegistryEntry) throws
    static func findByOriginalPath(_ path: String) -> (UUID, RegistryEntry)?
    static func findByUUID(_ uuid: UUID) -> RegistryEntry?
}
```

Update registry on every save and save-as.

### 3.5 Source Chain Manager

File: `JettyNotepad/SourceChain/SourceChainManager.swift`

```swift
class SourceChainManager {
    let fileStore: JNTFileStore

    func parentInfo() throws -> ParentInfo?      // Read from metadata
    func childrenInfo() throws -> [ChildInfo]    // Read from children table
    func hasChildren() throws -> Bool
    func addChild(uuid: UUID, path: String, forkTimestamp: Date, forkSeq: Int) throws

    func resolveParent() throws -> ParentResolution  // Check if parent still exists
    // .found(url) / .moved(newURL) / .unreachable(uuid) / .noParent
}
```

### 3.6 Mid-Tree Edit Warning

On first content edit in `JNTDocument.textDidChange`:

```swift
if !midTreeEditAcknowledged,
   let chain = sourceChainManager,
   (try? chain.hasChildren()) == true {
    let children = (try? chain.childrenInfo()) ?? []
    let alert = NSAlert()
    alert.messageText = "This document has \(children.count) downstream version(s)"
    alert.informativeText = "Editing here may make those versions' history incomplete. We recommend saving as a new version."
    alert.addButton(withTitle: "Save As New Version")  // Primary
    alert.addButton(withTitle: "Continue Editing")      // Secondary
    alert.beginSheetModal(for: ...) { response in
        if response == .alertFirstButtonReturn {
            self.runModalSavePanelForSaveOperation(.saveAsOperation)
        } else {
            self.midTreeEditAcknowledged = true
        }
    }
}
```

One prompt per editing session. Non-modal sheet.

### 3.7 Branch Tree Visualization

File: `JettyNotepad/History/BranchTreeViewController.swift`

Add "Branch Tree" tab to the History panel (alongside Timeline).

Use `NSOutlineView`:
- Root: the oldest ancestor (walk parent chain to find root)
- Each node: display name, modified date, reachability status
- Current document highlighted
- Double-click → open that file

Walk the tree:
1. From current document, follow `parent_uuid` chain to root
2. At each node, enumerate `children` table
3. For each child, check registry for path → if found, read its children recursively
4. If unreachable, show grayed out with "(not found)" label

### 3.8 History Folder Cleanup

File: `External/CleanupManager.swift`

```swift
class CleanupManager {
    static func scanForOrphans() throws -> [UUID]
    // Check each companion's originalPath — if file gone, it's orphan

    static func moveToOrphans(_ uuids: [UUID]) throws
    // Move from companions/ to orphans/

    static func purgeOldOrphans(olderThanDays: Int = 90) throws
    // Delete orphans older than threshold

    static func totalStorageBytes() throws -> Int64
    // Sum all .jnt files in JettyNote/

    static func cleanByCapacity(maxBytes: Int64) throws
    // Delete oldest companions until under limit

    static func cleanByCount(maxCount: Int) throws
    // Keep only N most recent companions

    static func clearHistoryForFile(uuid: UUID) throws
    // DELETE FROM snapshots in that .jnt

    static func clearAll() throws
    // rm -rf JettyNote/* and recreate structure
}
```

### 3.9 Preferences Panel (Basic)

Create a simple Preferences window (SwiftUI via `NSHostingView` is OK here):

**General tab:**
- Auto-save interval (picker: 30s / 1m / 2m / 5m / off)
- New file opens in: new tab / new window

**History tab:**
- JettyNote folder location (path display + "Change..." button)
- Storage used: `XX MB` (computed)
- Buttons: "Scan for Orphans", "Clean Up...", "Clear All History..."
- Max capacity: slider or text field (default: unlimited)
- Orphan retention: text field (default: 90 days)

### Phase 3 Gate

```bash
# G1: Build
cd /Users/vox/JNPT/JettyNotepad && xcodebuild -scheme JettyNotepad -configuration Debug build 2>&1 | grep "BUILD SUCCEEDED"

# G2: All tests pass (Phase 1 + 2 + 3)
xcodebuild -scheme JettyNotepad -configuration Debug test 2>&1 | grep -E "Test Suite .* passed"

# G3: External file creates companion
ls ~/Documents/JettyNote/companions/ | head -5
# Must have at least one UUID-prefix directory

# G4: Registry populated
python3 -c "
import json, sys
r = json.load(open('$HOME/Documents/JettyNote/registry.json'))
n = len(r) if isinstance(r, dict) else len(r.get('entries', {}))
print(f'{n} entries')
assert n > 0, 'Registry empty'
print('GATE 3-4 PASSED')
"

# G5: Mid-tree edit detection (part of unit tests)
# SourceChainManagerTests: file with children → hasChildren() returns true

# G6: Commit
cd /Users/vox/JNPT && git log --oneline | head -5
```

**Required unit tests:**
- `ExternalFileManagerTests`: companion URL generation, folder structure creation
- `RegistryManagerTests`: add/find/update/orphan detection
- `SourceChainManagerTests`: parent resolution, hasChildren, chain break handling
- `CleanupManagerTests`: orphan scan, capacity/count cleanup
- `MidTreeEditTests`: document with children triggers warning flag

---

## Work Strategy

### Per-Phase Workflow
1. Create all files (skeleton with signatures) → build → must compile
2. Implement each module → build after each file → catch errors immediately
3. Write tests alongside implementation → run after each module
4. Phase gate verification → all must pass
5. `git commit` with conventional format after each logical step

### Git Commit Format
```
feat: <description>
fix: <description>
test: <description>
refactor: <description>
chore: <description>
```

Initialize repo at start of Phase 1:
```bash
cd /Users/vox/JNPT && git init
git add .gitignore CLAUDE.md docs/ TODO.md AGENT_PROMPT_v1.1.0.md
git commit -m "chore: initial project structure with architecture docs"
```

### Fallback Decisions (Pre-Approved)

| Risk | Fallback | Trigger |
|------|----------|---------|
| diff-match-patch too complex in ~500 lines | Implement only `diffMain` + `patchMake` + `patchApply` (skip `match`). ~350 lines. | If exceeding 800 lines |
| Tab coloring via title suffix looks bad | Use NSToolbar with a colored status view instead | If user feedback says ugly |
| Branch tree with deep recursion is slow | Limit tree depth to 10 levels, lazy-load deeper nodes | If traversal > 500ms |
| NSOutlineView too complex for tree | Use flat `NSTableView` with indentation instead | If taking > 4h on tree UI alone |

### Invariants (Must Not Break)

1. Existing .jnt files openable after any change — schema migrations only, never destructive
2. Undo/Redo works across saves — save never clears undo stack
3. Auto-save never creates generations — only Save As does
4. External files never modified beyond user's explicit save
5. UUID immutable once assigned
6. App launches in < 500ms on 2020 MacBook Air
7. SQLite WAL mode always enabled
8. All writes inside transactions
