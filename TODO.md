# JettyNotepad — Deferred Work (Phase 4-5)

> Phase 1-3 covered in `AGENT_PROMPT_v1.1.0.md`
> These phases start after Phase 3 Gate passes.

---

## Phase 4: Enhancement Layer

**Prerequisite:** Phase 3 complete, all gates passed.

### 4.1 Markdown Inline Rendering

- Subclass `NSTextStorage` → `JNTTextStorage`
- Override `processEditing()` to parse Markdown syntax and apply `NSAttributedString` attributes
- Patterns: `# heading`, `**bold**`, `*italic*`, `~~strikethrough~~`, `` `code` ``, `[link](url)`, `- list`
- Toggle: Menu "Format > Markdown Rendering" (Cmd+Shift+M)
- Global default in Preferences
- **Fallback decision:** If inline rendering too complex, degrade to syntax highlighting only (color tokens, no size/weight changes). Upgrade in future version.

### 4.2 Spell Check Configuration

- NSTextView has built-in spell check via NSSpellChecker — just configure
- Preferences: enable/disable spell check, auto-correct, grammar check (per-app default)
- Menu: "Edit > Spelling and Grammar" submenu (standard macOS)
- Per-file-type control (e.g., disable for .log)

### 4.3 Quick Look Extension

- New Xcode target: `JettyNotepadQuickLook` (Quick Look Preview Extension)
- Opens SQLite → `SELECT content FROM document WHERE id = 1` → render as plain text
- ~50 lines of code
- Register in Info.plist with `.jnt` UTI

### 4.4 Spotlight Importer

- New Xcode target: `JettyNotepadSpotlight` (Spotlight Importer)
- Index: title (display_name), content (full text), modification date
- Opens SQLite read-only → extracts text + metadata

### 4.5 Export

- Menu: "File > Export As > Plain Text (.txt)" / "Markdown (.md)"
- NSSavePanel with format selection
- Warning: "Export does not include history, snapshots, or branch information."

---

## Phase 5: AI Extensions (Future)

**Prerequisite:** Phase 4 complete. macOS 26 (Tahoe) API availability confirmed.

### 5.1 AI Service Protocol

```swift
protocol AIService {
    func rewrite(text: String, style: RewriteStyle) async throws -> String
    func summarize(text: String, maxLength: Int?) async throws -> String
    func write(prompt: String, context: String?) async throws -> String
    var isAvailable: Bool { get }
    var modelName: String { get }
}
```

### 5.2 Apple Intelligence (macOS 26+)

- Use Foundation Models API / Writing Tools API when available
- Check runtime availability with `#available(macOS 26, *)`
- **Primary path if API ships; fallback to local model if not**

### 5.3 Local Model Service

- Support loading GGUF models via llama.cpp Swift bindings or Core ML `.mlmodelc`
- Preferences: model file picker, temperature, max generation length
- Prompt templates for Rewrite/Summarize/Write tasks

### 5.4 AI Panel UI

- Sheet or sidebar: "Tools > AI Assistant" (Cmd+Shift+A)
- Rewrite: style dropdown (Professional/Casual/Concise/Detailed/Friendly) → preview → Accept/Revert
- Summarize: generate summary in new tab
- Write: prompt input → generate at cursor
- Context menu integration for selected text

### 5.5 AI Preferences

- Provider: Apple Intelligence / Local Model / Disabled
- Local model path picker
- Advanced: temperature, max tokens

---

## Notes

- Phase 4 features are independent of each other — can be implemented in any order
- Phase 5 depends on macOS 26 API availability — monitor WWDC announcements
- Both phases should maintain all Phase 1-3 invariants (see AGENT_PROMPT)
