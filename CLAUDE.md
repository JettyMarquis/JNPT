# JettyNotepad

macOS native text editor with built-in version history and branch tracking.

## Tech Stack

- **Language:** Swift 5.9+ with AppKit (NOT SwiftUI for main UI)
- **Editor Engine:** NSTextView + TextKit 1
- **Storage:** SQLite for .jnt file format (WAL mode, atomic writes)
- **Diff Algorithm:** diff-match-patch (clean-room Swift implementation, ~500 lines, zero third-party)
- **Deployment Target:** macOS 13 (Ventura)+

## Build

```bash
cd /Users/vox/JNPT/JettyNotepad
xcodebuild -scheme JettyNotepad -configuration Debug build
```

## Test

```bash
cd /Users/vox/JNPT/JettyNotepad
xcodebuild -scheme JettyNotepad -configuration Debug test
```

## Architecture

See `docs/ARCHITECTURE.md` for full architecture documentation.

## Key Constraints

- `NSDocument` subclass for document lifecycle — do not create custom lifecycle
- `NSTabbedWindow` for tab management — `tabbingMode = .preferred`
- WAL mode for all SQLite connections — `PRAGMA journal_mode=WAL`
- 100 snapshot limit per document — enforced by SQLite trigger
- Save never creates new generations; only Save As does
- Undo/Redo persists across saves — save never clears undo stack
- Tab coloring via custom view (title suffix indicators), not private API
- Zero third-party dependencies in Phase 1 — system frameworks only
- `.jnt` files opened from disk are untrusted input — validate with `PRAGMA integrity_check`

## Project Structure

```
JNPT/
├── CLAUDE.md                    # This file
├── LICENSE                      # MIT
├── README.md
├── CHANGELOG.md
├── AGENT_PROMPT_v1.1.0.md       # Phase 1-3 long-running agent prompt
├── TODO.md                      # Phase 4-5 deferred work
├── docs/
│   ├── ARCHITECTURE.md
│   ├── competitive-research.md
│   └── jnt-format-and-branch-system-spec.md
└── JettyNotepad/                # Xcode project (Phase 1)
    ├── JettyNotepad/
    │   ├── App/
    │   ├── Document/
    │   ├── Editor/
    │   ├── Storage/
    │   ├── Window/
    │   ├── AutoSave/
    │   ├── Snapshot/            # Phase 2
    │   ├── History/             # Phase 2
    │   ├── External/            # Phase 3
    │   └── SourceChain/         # Phase 3
    └── JettyNotepadTests/
```
