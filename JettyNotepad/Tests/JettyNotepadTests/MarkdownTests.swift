import Foundation
import AppKit
import JettyNotepadKit

func runMarkdownTests() {
    print("\n--- Markdown / JNTTextStorage Tests ---")

    // Helper: create a storage with text, optionally with markdown enabled
    func makeStorage(text: String, markdown: Bool = false) -> JNTTextStorage {
        let ts = JNTTextStorage()
        ts.markdownRenderingEnabled = markdown
        ts.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        return ts
    }

    test("JNTTextStorage: string property round-trips") {
        let ts = makeStorage(text: "Hello, world!")
        try assertEqual(ts.string, "Hello, world!")
    }

    test("JNTTextStorage: length matches input") {
        let ts = makeStorage(text: "abc")
        try assertEqual(ts.length, 3)
    }

    test("JNTTextStorage: empty storage has zero length") {
        let ts = JNTTextStorage()
        try assertEqual(ts.length, 0)
    }

    test("Markdown disabled: no bold attribute on **bold** text") {
        let ts = makeStorage(text: "**bold**", markdown: false)
        let font = ts.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        try assertTrue(!isBold, "Should not be bold when markdown is disabled")
    }

    test("Markdown enabled: **bold** gets bold font weight") {
        let ts = makeStorage(text: "**bold**", markdown: true)
        let font = ts.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        try assertNotNil(font)
        let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        try assertTrue(isBold, "Expected bold font trait")
    }

    test("Markdown enabled: # Heading 1 gets larger font") {
        let ts = makeStorage(text: "# Title Here", markdown: true)
        let font = ts.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        try assertNotNil(font)
        try assertGreaterThan(font!.pointSize, JNTTextStorage.baseFont.pointSize)
    }

    test("Markdown enabled: ## Heading 2 smaller than # Heading 1") {
        let h1 = makeStorage(text: "# H1", markdown: true)
        let h2 = makeStorage(text: "## H2", markdown: true)
        let f1 = h1.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let f2 = h2.attribute(.font, at: 3, effectiveRange: nil) as? NSFont
        try assertNotNil(f1)
        try assertNotNil(f2)
        try assertGreaterThan(f1!.pointSize, f2!.pointSize)
    }

    test("Markdown enabled: `code` gets background color") {
        let ts = makeStorage(text: "`code`", markdown: true)
        let bg = ts.attribute(.backgroundColor, at: 1, effectiveRange: nil)
        try assertNotNil(bg)
    }

    test("Markdown enabled: ~~strike~~ gets strikethrough") {
        let ts = makeStorage(text: "~~strike~~", markdown: true)
        let val = ts.attribute(.strikethroughStyle, at: 2, effectiveRange: nil)
        try assertNotNil(val)
    }

    test("Markdown enabled: [text](url) link portion gets underline") {
        let ts = makeStorage(text: "[click here](https://example.com)", markdown: true)
        // "click here" starts at index 1
        let underline = ts.attribute(.underlineStyle, at: 2, effectiveRange: nil)
        try assertNotNil(underline)
    }

    test("Toggle off: attributes reset to base font") {
        let ts = makeStorage(text: "**bold**", markdown: true)
        // Confirm bold is applied
        let boldFont = ts.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        try assertTrue(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false,
                       "Should be bold before toggle")
        // Toggle off
        ts.markdownRenderingEnabled = false
        ts.invalidateAndReapplyStyles()
        let plainFont = ts.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let isBold = plainFont?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        try assertTrue(!isBold, "Should not be bold after toggle off")
    }

    test("Markdown enabled: bullet list marker gets color") {
        let ts = makeStorage(text: "- item one", markdown: true)
        let color = ts.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        try assertNotNil(color)
        // The bullet marker should NOT be the default text color
        try assertTrue(color != NSColor.textColor, "Bullet should have distinct foreground color")
    }

    test("Markdown enabled: plain text outside markers uses base font") {
        let ts = makeStorage(text: "just plain text", markdown: true)
        let font = ts.attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        try assertNotNil(font)
        let isBold = font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
        try assertTrue(!isBold, "Plain text should not be bold")
    }
}
