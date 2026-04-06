import AppKit
import UniformTypeIdentifiers

public class JNTDocumentController: NSDocumentController {
    public override var documentClassNames: [String] {
        ["JNTDocument"]
    }

    public override var defaultType: String? {
        "com.jettymarquis.jettynotepad.jnt"
    }

    public override func documentClass(forType typeName: String) -> AnyClass? {
        JNTDocument.self
    }

    public override func typeForContents(of url: URL) throws -> String {
        switch url.pathExtension.lowercased() {
        case "jnt": return "com.jettymarquis.jettynotepad.jnt"
        case "txt": return "public.plain-text"
        case "md", "markdown": return "net.daringfireball.markdown"
        default: return try super.typeForContents(of: url)
        }
    }

    public override func displayName(forType typeName: String) -> String {
        switch typeName {
        case "com.jettymarquis.jettynotepad.jnt": return "JettyNotepad Document"
        case "public.plain-text": return "Plain Text"
        case "net.daringfireball.markdown": return "Markdown"
        default: return super.displayName(forType: typeName) ?? typeName
        }
    }

    public override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        var contentTypes: [UTType] = []
        if let jnt = UTType(filenameExtension: "jnt") { contentTypes.append(jnt) }
        if let txt = UTType.plainText as UTType? { contentTypes.append(txt) }
        if let md = UTType(filenameExtension: "md") { contentTypes.append(md) }
        openPanel.allowedContentTypes = contentTypes
        return super.runModalOpenPanel(openPanel, forTypes: types)
    }
}
