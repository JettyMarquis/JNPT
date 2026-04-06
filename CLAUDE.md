# JettyNotepad

macOS native text editor with built-in version history and branch tracking.

## Tech Stack
- Swift 5.9+ / AppKit (NOT SwiftUI for main UI)
- SQLite for .jnt file format (WAL mode)
- diff-match-patch (clean-room Swift, ~500 lines) — Phase 2
- Deployment target: macOS 13+
- Build system: Swift Package Manager

## Build
```
cd /Users/vox/JNPT/JettyNotepad && swift build
```

## Test
```
cd /Users/vox/JNPT/JettyNotepad && swift test
```

## Run
```
cd /Users/vox/JNPT/JettyNotepad && swift run JettyNotepad
```

## Architecture
See docs/ARCHITECTURE.md

## Project Layout
- `Sources/JettyNotepadKit/` — Library: all app logic (Storage, Document, Editor, Window, AutoSave)
- `Sources/JettyNotepad/` — Executable: just main.swift entry point
- `Tests/JettyNotepadTests/` — Unit tests
- `scripts/bundle.sh` — Package binary into .app bundle

## Critical Rules
1. AppKit for main UI. SwiftUI ONLY via NSHostingView for Preferences.
2. NSDocument subclass is the document model.
3. SQLite = .jnt. Use sqlite3 C API via Swift bridging. No Core Data. No GRDB.
4. Reverse diff chain: current content in full; older versions reconstructed backward.
5. Save != new generation. Only Save As creates parent-child links.
6. Undo persists across saves.
7. macOS 13+ only. No APIs from 14+.
8. Zero third-party dependencies in Phase 1.
