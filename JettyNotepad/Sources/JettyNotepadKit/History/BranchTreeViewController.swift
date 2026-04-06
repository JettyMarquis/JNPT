import AppKit

/// Node in the branch tree.
public class BranchTreeNode: NSObject {
    public let uuid: UUID
    public let displayName: String
    public let modifiedDate: String
    public let isReachable: Bool
    public let isCurrent: Bool
    public var children: [BranchTreeNode] = []

    public init(uuid: UUID, displayName: String, modifiedDate: String,
                isReachable: Bool, isCurrent: Bool) {
        self.uuid = uuid
        self.displayName = displayName
        self.modifiedDate = modifiedDate
        self.isReachable = isReachable
        self.isCurrent = isCurrent
    }
}

/// Branch tree visualization using NSOutlineView.
public class BranchTreeViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private var outlineView: NSOutlineView!
    private var rootNodes: [BranchTreeNode] = []
    private weak var jntDocument: JNTDocument?

    public init(document: JNTDocument) {
        self.jntDocument = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        scrollView.hasVerticalScroller = true

        outlineView = NSOutlineView()
        outlineView.headerView = nil
        outlineView.rowHeight = 36

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("tree"))
        col.width = 380
        outlineView.addTableColumn(col)
        outlineView.outlineTableColumn = col

        outlineView.dataSource = self
        outlineView.delegate = self

        scrollView.documentView = outlineView
        self.view = scrollView
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        buildTree()
        outlineView.reloadData()
        outlineView.expandItem(nil, expandChildren: true)
    }

    private func buildTree() {
        guard let doc = jntDocument, let store = doc.fileStore else { return }
        let currentUUID = doc.fileUUID

        // Walk parent chain to find root
        let chain = SourceChainManager(fileStore: store)
        var rootUUID = currentUUID
        var rootPath: String? = store.url.path

        if let (foundRoot, foundURL) = try? chain.findRoot(maxDepth: 10) {
            rootUUID = foundRoot
            rootPath = foundURL?.path
        }

        // Build tree from root
        let root = buildNode(uuid: rootUUID, path: rootPath, currentUUID: currentUUID, depth: 0)
        rootNodes = [root]
    }

    private func buildNode(uuid: UUID, path: String?, currentUUID: UUID, depth: Int) -> BranchTreeNode {
        guard depth < 10 else {
            return BranchTreeNode(uuid: uuid, displayName: "...", modifiedDate: "",
                                  isReachable: false, isCurrent: false)
        }

        var name = uuid.uuidString.prefix(8) + "..."
        var modDate = ""
        var isReachable = false
        var childNodes: [BranchTreeNode] = []

        if let path = path, FileManager.default.fileExists(atPath: path) {
            isReachable = true
            if let store = try? JNTFileStore(url: URL(fileURLWithPath: path)) {
                defer { store.close() }
                name = Substring((try? store.readMetadata(key: "display_name")) ?? String(name))
                if let state = try? store.readDocumentState() {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .short
                    modDate = formatter.string(from: state.modifiedAt)
                }
                if let children = try? store.readChildren() {
                    for child in children {
                        let childNode = buildNode(
                            uuid: child.childUUID, path: child.childPath,
                            currentUUID: currentUUID, depth: depth + 1)
                        childNodes.append(childNode)
                    }
                }
            }
        } else if let entry = RegistryManager.findByUUID(uuid) {
            name = Substring(entry.displayName)
            isReachable = FileManager.default.fileExists(atPath: entry.jntPath)
        }

        let node = BranchTreeNode(
            uuid: uuid, displayName: String(name), modifiedDate: modDate,
            isReachable: isReachable, isCurrent: uuid == currentUUID)
        node.children = childNodes
        return node
    }

    // MARK: - NSOutlineViewDataSource

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNodes.count }
        return (item as? BranchTreeNode)?.children.count ?? 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootNodes[index] }
        return (item as! BranchTreeNode).children[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return ((item as? BranchTreeNode)?.children.count ?? 0) > 0
    }

    // MARK: - NSOutlineViewDelegate

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? BranchTreeNode else { return nil }

        let cell = NSTableCellView()
        let titleField = NSTextField(labelWithString: node.displayName)
        titleField.font = .systemFont(ofSize: 13, weight: node.isCurrent ? .bold : .regular)

        if !node.isReachable {
            titleField.textColor = .tertiaryLabelColor
            titleField.stringValue += " (not found)"
        } else if node.isCurrent {
            titleField.textColor = .controlAccentColor
        }

        let dateField = NSTextField(labelWithString: node.modifiedDate)
        dateField.font = .systemFont(ofSize: 10)
        dateField.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [titleField, dateField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }
}
