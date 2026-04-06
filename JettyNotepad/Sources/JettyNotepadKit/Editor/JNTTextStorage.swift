import AppKit

public class JNTTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()
    public var markdownRenderingEnabled = false

    // MARK: - Required NSTextStorage overrides

    public override var string: String { backing.string }

    public override func attributes(at location: Int,
                                    effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    public override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
    }

    public override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    /// Force a full style refresh without a character edit. Use when toggling `markdownRenderingEnabled`.
    public func invalidateAndReapplyStyles() {
        guard length > 0 else { return }
        beginEditing()
        edited(.editedAttributes, range: NSRange(location: 0, length: length), changeInLength: 0)
        endEditing()
    }

    public override func processEditing() {
        if markdownRenderingEnabled {
            applyMarkdownStyles()
        } else {
            applyPlainStyles()
        }
        // Extend invalidated range so layout managers re-render the full document.
        if length > 0 {
            edited(.editedAttributes, range: NSRange(location: 0, length: length), changeInLength: 0)
        }
        super.processEditing()
    }

    // MARK: - Fonts

    public static let baseFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    private static let codeFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    private static let boldFont = NSFont.monospacedSystemFont(ofSize: 14, weight: .bold)

    private static func headingFont(level: Int) -> NSFont {
        NSFont.systemFont(ofSize: 14 + CGFloat(7 - level) * 2, weight: .bold)
    }

    private static func italicFont() -> NSFont {
        let desc = baseFont.fontDescriptor.withSymbolicTraits(.italic)
        return NSFont(descriptor: desc, size: 14) ?? baseFont
    }

    // MARK: - Style helpers (operate on backing directly to avoid re-entrant edited calls)

    private func resetAttributes(in range: NSRange) {
        backing.setAttributes([
            .font: JNTTextStorage.baseFont,
            .foregroundColor: NSColor.textColor
        ], range: range)
        backing.removeAttribute(.backgroundColor, range: range)
        backing.removeAttribute(.strikethroughStyle, range: range)
        backing.removeAttribute(.underlineStyle, range: range)
        backing.removeAttribute(.link, range: range)
    }

    // MARK: - Plain styles

    private func applyPlainStyles() {
        guard length > 0 else { return }
        resetAttributes(in: NSRange(location: 0, length: length))
    }

    // MARK: - Markdown styles

    private func applyMarkdownStyles() {
        guard length > 0 else { return }
        let full = NSRange(location: 0, length: length)
        resetAttributes(in: full)

        let str = string
        applyHeadings(str)
        applyBold(str)
        applyItalic(str)
        applyStrikethrough(str)
        applyCode(str)
        applyLinks(str)
        applyBullets(str)
    }

    private func applyHeadings(_ str: String) {
        guard let regex = try? NSRegularExpression(pattern: "^(#{1,6})\\s",
                                                   options: .anchorsMatchLines) else { return }
        let nsStr = str as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        for match in regex.matches(in: str, range: full) {
            let lineRange = nsStr.lineRange(for: match.range)
            let level = min(nsStr.substring(with: match.range(at: 1)).count, 6)
            backing.addAttributes([.font: JNTTextStorage.headingFont(level: level)], range: lineRange)
        }
    }

    private func applyBold(_ str: String) {
        guard let regex = try? NSRegularExpression(pattern: "(\\*\\*|__)(.+?)\\1",
                                                   options: []) else { return }
        let nsStr = str as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        for match in regex.matches(in: str, range: full) {
            backing.addAttributes([.font: JNTTextStorage.boldFont], range: match.range)
        }
    }

    private func applyItalic(_ str: String) {
        // Single * or _, not preceded/followed by same marker (avoids bold runs)
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\*)(\\*|_)(?!\\1)(.+?)(?<!\\1)\\1(?!\\1)",
                                                   options: []) else { return }
        let nsStr = str as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        for match in regex.matches(in: str, range: full) {
            // Skip if already bold
            let existingFont = backing.attribute(.font, at: match.range.location,
                                                 effectiveRange: nil) as? NSFont
            if existingFont?.fontDescriptor.symbolicTraits.contains(.bold) != true {
                backing.addAttributes([.font: JNTTextStorage.italicFont()], range: match.range)
            }
        }
    }

    private func applyStrikethrough(_ str: String) {
        guard let regex = try? NSRegularExpression(pattern: "~~(.+?)~~",
                                                   options: []) else { return }
        let nsStr = str as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        for match in regex.matches(in: str, range: full) {
            backing.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue],
                                   range: match.range)
        }
    }

    private func applyCode(_ str: String) {
        guard let regex = try? NSRegularExpression(pattern: "`([^`]+)`",
                                                   options: []) else { return }
        let nsStr = str as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        for match in regex.matches(in: str, range: full) {
            backing.addAttributes([
                .font: JNTTextStorage.codeFont,
                .backgroundColor: NSColor.quaternaryLabelColor
            ], range: match.range)
        }
    }

    private func applyLinks(_ str: String) {
        guard let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)]+)\\)",
                                                   options: []) else { return }
        let nsStr = str as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        for match in regex.matches(in: str, range: full) {
            let textRange = match.range(at: 1)
            backing.addAttributes([
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: textRange)
        }
    }

    private func applyBullets(_ str: String) {
        guard let regex = try? NSRegularExpression(pattern: "^[\\-\\*] ",
                                                   options: .anchorsMatchLines) else { return }
        let nsStr = str as NSString
        let full = NSRange(location: 0, length: nsStr.length)
        for match in regex.matches(in: str, range: full) {
            backing.addAttributes([.foregroundColor: NSColor.systemBlue], range: match.range)
        }
    }
}
