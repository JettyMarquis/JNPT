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
        if url.pathExtension.lowercased() == "jnt" {
            return "com.jettymarquis.jettynotepad.jnt"
        }
        return try super.typeForContents(of: url)
    }

    public override func displayName(forType typeName: String) -> String {
        if typeName == "com.jettymarquis.jettynotepad.jnt" {
            return "JettyNotepad Document"
        }
        return super.displayName(forType: typeName) ?? typeName
    }

    public override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        if let jntType = UTType(filenameExtension: "jnt") {
            openPanel.allowedContentTypes = [jntType]
        }
        return super.runModalOpenPanel(openPanel, forTypes: types)
    }
}
