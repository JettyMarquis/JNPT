# JettyNotepad

A lightweight macOS text editor that keeps your document's history — like a notepad with version control built in.

## What It Does

JettyNotepad looks and feels like a simple notepad, but under the hood it tracks every version of your document:

- **Save** updates your file and records a snapshot of the change
- **Save As** creates a new branch in your document's history
- **History** lets you browse and restore any of the last 100 versions
- **External files** (.txt, .md) get a companion `.jnt` file that preserves their history

## Tech Stack

| Component | Choice |
|-----------|--------|
| Language | Swift 5.9+ |
| Framework | AppKit (macOS native) |
| Editor | NSTextView + TextKit 1 |
| Storage | SQLite (.jnt files) |
| Diff Engine | diff-match-patch (clean-room) |
| Target | macOS 13 (Ventura)+ |

## Build

```bash
cd JettyNotepad
xcodebuild -scheme JettyNotepad -configuration Debug build
```

## Test

```bash
cd JettyNotepad
xcodebuild -scheme JettyNotepad -configuration Debug test
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for architecture decisions, SQLite schema, module diagram, and save/branch state machines.

## Roadmap

| Phase | Status | Scope |
|-------|--------|-------|
| Phase 1 | Planned | MVP — tabs, .jnt read/write, auto-save, session restore |
| Phase 2 | Planned | History — snapshots, timeline UI, Save As generations |
| Phase 3 | Planned | External files, branching, source chain, cleanup |
| Phase 4 | TODO | Markdown rendering, spell check, Quick Look, export |
| Phase 5 | TODO | AI writing assistance (local models) |

## License

[MIT](LICENSE)
