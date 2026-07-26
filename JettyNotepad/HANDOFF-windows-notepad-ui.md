# HANDOFF — Windows Notepad-style Multi-Tab UI (paused)

**Paused:** 2026-07-25
**Branch merged:** `feature/windows-notepad-ui` → `mvp` (squash)
**Full implementation plan (Phase 2–4 detail, all review findings):** `~/.claude/plans/keen-brewing-salamander.md` — kept up to date, read it before resuming.

## What this feature is

Reworking JettyNotepad's UI to look like Windows 11 Notepad: pill-shaped tabs in the titlebar, in-window File/Edit/View menu row (popping the same `NSMenu` as the system menu bar), an undo/redo button row above the editor. Full rationale and the ~35 review findings that shaped the design are in the plan file.

## Status snapshot

- Build: `swift build` passes clean.
- Tests: `swift run JettyNotepadTests` → **105/105 passing**.
- Smoke test: `swift run JettyNotepad` launches without crashing (verified via `timeout` + checking `~/Library/Logs/DiagnosticReports` for new crash reports).
- **No interactive/manual GUI testing has been done.** This environment has no tool that can drive native AppKit UI (only Chrome browser automation is available, which doesn't apply here). Everything below marked "manual" has only been verified by reading code, never by running the app and clicking through it.

## Done: Phase 0 — pure refactor, no behavior change

- `Sources/JettyNotepadKit/App/MenuBuilder.swift` — extracted menu-bar construction out of `AppDelegate`; owns `fileMenu`/`editMenu`/`viewMenu` and all their target/action wiring.
- `EditorViewController.editorDidBecomeActive()` — extracted from `viewDidAppear()` so it can be called explicitly when a tab is mounted, instead of relying on the view lifecycle to fire it.
- `JNTDocument.editorViewController` — changed to a `weak var` set directly by the shell, instead of being derived from window controllers.
- All 91 pre-existing tests stayed green.

## Done: Phase 1 — shared window + single-document architecture

- **`Window/ShellWindowController.swift`** (new, 380 lines) — the one real `NSWindow` for the whole app. `isRestorable = true`, stable `identifier`, registered `restorationClass` (conforms to `NSWindowRestoration`). Owns `[TabItem]` + `selectedIndex`. `addTab`, `selectTab(at:)`, `selectTab(for:)`, `closeTab` (with a `TabItem.isClosing` reentrancy guard), `windowShouldClose` (serial `canClose` chain across tabs), `refreshTab(for:)` (only writes `window.title` when the tab is active), `validateMenuItem(_:)` (recreates `NSDocument`'s own Save/Revert grey-out logic).
- **`Window/RestorableSession.swift`** (new) — plain `Codable` value type for "which tabs were open, in what state" (`.saved(url:)` / `.draft(autosaveURL:cursor:scroll:)` + `selectedIndex`), independent of `NSCoder` so it's unit-testable directly. `ShellWindowController` does a thin struct↔`NSData`↔`NSCoder` adapter around it, using typed/secure decoding (`decodeObject(of: NSData.self, forKey:)`).
- **`Window/ShellContentViewController.swift`** (new) — window's root content VC, 3 blocks (menu row / undo-redo row / content container — tab strip is titlebar-accessory territory, Phase 4). `mount(_:)`/`unmount(_:)` via `addChild`/`removeFromParent`.
- **`Window/DocumentProxyWindowController.swift`** (new) — zero-window proxy (`init(window: nil)`) that each `JNTDocument.makeWindowControllers()` creates; `showWindow(_:)` brings the shared window forward and selects the matching tab.
- **`Window/TabItem.swift`** (new) — per-tab bookkeeping (document, editor, proxy, display name, dirty flag, `isClosing`).
- **`Document/JNTDocument.swift`** — `makeWindowControllers()` now routes through `ShellWindowController.addTab`; added `windowForSheet` override; removed the old `encodeRestorableState`/`restoreState` overrides (moved to the shell).
- **`Editor/EditorViewController.swift`** — `undoManager(for:)` returns `document?.undoManager` (per-document undo isolation, tested in `ShellWindowControllerTests`).
- **`App/AppDelegate.swift`** — `setupMenuBar()` moved into `MenuBuilder`; File menu actions point at `ShellWindowController.shared` explicitly; plus two fixes added after Phase 1 landed:
  - `NSApp.activate(ignoringOtherApps: true)` in `applicationDidFinishLaunching` — without it, `swift run` launches produce a window that never receives keyboard focus (this was the original bug report: "无法录入内容").
  - `applicationSupportsSecureRestorableState(_:) -> true` — without this opt-in, macOS 12+ can skip or downgrade window-state restoration entirely.
  - `applicationShouldOpenUntitledFile(_:)` now returns `ShellWindowController.shared.tabs.isEmpty` instead of unconditional `true` — avoids a spurious extra blank tab on a relaunch that already restored a session.
- Deleted `Window/JNTWindowController.swift` (superseded by the shared-window architecture).
- New tests: `RestorableSessionTests.swift` (5), `ShellWindowControllerTests.swift` (8) — both use a fresh `ShellWindowController()` per test, never `.shared`, to avoid cross-test tab leakage.

Commits (now squashed into one on `mvp`, original SHAs for reference):
`58cd286` (Phase 0), `40e2356` (Phase 1), `73ea6fb` (activation fix), `1cd7620` (secure restorable state + untitled-file fix).

## ⚠️ Not done: Phase 1's own manual verification gate

The plan's explicit rule: **"任何一项验证不通过,先解决再进入 Phase 2,不要带着假设往下叠"** (if any item fails, fix it before Phase 2 — don't stack further work on unverified assumptions). None of these have been confirmed by actually running the app:

1. **Session restore** — quit and relaunch `JettyNotepad.app` (not `swift run` — real restoration needs the app bundle/Info.plist). Do previously open tabs come back? Does `restoreState` actually fire (add a `print()`/breakpoint in `ShellWindowController.restoreState(with:)` if it's unclear)?
2. **Font-size shortcuts** — press ⌘+ / ⌘- while editing. Does the font size change? (Code-review conclusion: should work, since `NSViewController` wires `view.nextResponder → viewController` automatically once the view is attached, independent of `addChild` — but this has not been run.)
3. **Save / Save As / Revert to Saved / dirty-close** — does Save grey out correctly when clean, Revert grey out with no file, does closing a dirty tab show the expected save-prompt sheet?
4. **Basic typing** — does keyboard input work at all via `swift run JettyNotepad` now that the activation fix is in place? (This was the original bug report.)

**Do these 4 checks first when resuming**, before writing any Phase 2 code.

## TODO — not started

- **Phase 2 — real multi-tab**: `TabStripView`/`TabPillView` (titlebar accessory), full `addTab`/`selectTab`/`closeTab` behavior with multiple concurrent tabs, `windowShouldClose` serial chain across N tabs, restore-state extended to multiple tabs (strict serial reopen + index clamping already implemented in `RestorableSession`/`ShellWindowController`, just needs the UI to actually create multiple tabs to exercise it end-to-end).
- **Phase 3 — chrome rows**: `MenuRowView` (File/Edit/View text buttons + gear, popping the same `NSMenu`), `UndoRedoBarView` (two SF Symbol buttons, immediate enable-state refresh on tab switch).
- **Phase 4 — titlebar polish**: `titlebarAppearsTransparent`/`.fullSizeContentView`, `NSTitlebarAccessoryViewController(layoutAttribute: .leading)` hosting the tab strip, manual check of whether traffic-light spacing is really automatic (plan flags this as uncertain — `.leading` is documented but the auto-avoidance behavior needs a real run to confirm).
- **Full manual QA checklist** (see plan file's "测试策略" section) — New/New Tab/Open/Open Recent/Save/Save As/Revert/Close/Print, Undo/Redo per-tab isolation, Cut/Copy/Paste/Select All/Find, History, font size, Preferences gear, rapid tab-close races, dark mode, VoiceOver.

## How to resume

```bash
cd /Users/vox/JNPT/JettyNotepad
git checkout mvp && git pull
git checkout -b feature/windows-notepad-ui-phase2
swift build && swift run JettyNotepadTests   # confirm still 105/105 before touching anything
```

Then:
1. Run the 4 manual verification items above via `swift run JettyNotepad` (or build+run the `.app` bundle via `scripts/bundle.sh` for the session-restore check specifically). Fix anything that fails before writing new code.
2. Open `~/.claude/plans/keen-brewing-salamander.md`, jump to "Phase 2 —— 真正的多标签" and follow it — it has the exact files, methods, and edge cases (reentrant close guard, `selectedIndex` adjustment math, `autoSaveManager.stop()` ordering) already designed and reviewed.
3. Keep committing per-phase (`swift build && swift run JettyNotepadTests` green after each), same cadence as Phase 0/1.
