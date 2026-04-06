import AppKit

/// History panel: split view with timeline list (left) and content preview (right).
/// Accessible via View > History (Cmd+Shift+H).
public class HistoryPanelController: NSWindowController {
    private var jntDocument: JNTDocument?
    private var splitVC: NSSplitViewController!
    private var timelineVC: HistoryTimelineViewController!
    private var previewVC: HistoryPreviewViewController!

    public convenience init(document: JNTDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "History — \(JNTFileStore.displayNameFromContent(document.content))"
        window.center()
        window.minSize = NSSize(width: 600, height: 400)

        self.init(window: window)
        self.jntDocument = document

        timelineVC = HistoryTimelineViewController(document: document)
        previewVC = HistoryPreviewViewController()

        timelineVC.onSelect = { [weak self] snapshot, reconstructed in
            self?.previewVC.showContent(reconstructed, snapshot: snapshot,
                                        currentContent: document.content)
        }

        timelineVC.onBranchFromHere = { [weak self] snapshot, reconstructed in
            self?.branchFromSnapshot(snapshot, content: reconstructed)
        }

        let timelineItem = NSSplitViewItem(contentListWithViewController: timelineVC)
        timelineItem.minimumThickness = 250
        timelineItem.maximumThickness = 400

        let previewItem = NSSplitViewItem(viewController: previewVC)
        previewItem.minimumThickness = 300

        splitVC = NSSplitViewController()
        splitVC.addSplitViewItem(timelineItem)
        splitVC.addSplitViewItem(previewItem)

        window.contentViewController = splitVC
    }

    private func branchFromSnapshot(_ snapshot: SnapshotSummary, content: String) {
        guard let doc = jntDocument else { return }
        // Set the content to the reconstructed version, then trigger Save As
        doc.content = content
        doc.editorViewController?.textView.string = content
        doc.updateChangeCount(.changeDone)
        // Trigger Save As panel
        NSDocumentController.shared.currentDocument?.runModalSavePanel(
            for: .saveAsOperation,
            delegate: nil,
            didSave: nil,
            contextInfo: nil
        )
    }
}

// MARK: - Timeline View Controller

public class HistoryTimelineViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private weak var document: JNTDocument?
    private var tableView: NSTableView!
    private var snapshots: [SnapshotSummary] = []
    var onSelect: ((SnapshotSummary, String) -> Void)?
    var onBranchFromHere: ((SnapshotSummary, String) -> Void)?

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    init(document: JNTDocument) {
        self.document = document
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        scrollView.hasVerticalScroller = true

        tableView = NSTableView()
        tableView.headerView = nil
        tableView.rowHeight = 52

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("snapshot"))
        col.width = 280
        tableView.addTableColumn(col)

        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView

        // Branch button at bottom
        let branchButton = NSButton(title: "Branch From Selected", target: self,
                                    action: #selector(branchAction))
        branchButton.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 600))
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(branchButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: branchButton.topAnchor, constant: -8),
            branchButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            branchButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            branchButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            branchButton.heightAnchor.constraint(equalToConstant: 30),
        ])

        self.view = container
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        reload()
    }

    func reload() {
        guard let store = document?.fileStore else { return }
        snapshots = (try? store.readSnapshotManifest()) ?? []
        tableView.reloadData()
    }

    // MARK: - NSTableViewDataSource

    public func numberOfRows(in tableView: NSTableView) -> Int {
        snapshots.count
    }

    // MARK: - NSTableViewDelegate

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let snap = snapshots[row]
        let cell = NSTableCellView()

        let titleField = NSTextField(labelWithString: typeLabel(snap.snapshotType))
        titleField.font = .systemFont(ofSize: 13, weight: .medium)

        let dateField = NSTextField(labelWithString: dateFormatter.string(from: snap.timestamp))
        dateField.font = .systemFont(ofSize: 11)
        dateField.textColor = .secondaryLabelColor

        let sizeStr: String
        if let after = snap.contentLengthAfter {
            sizeStr = ByteCountFormatter.string(fromByteCount: Int64(after), countStyle: .file)
        } else {
            sizeStr = ""
        }
        let sizeField = NSTextField(labelWithString: sizeStr)
        sizeField.font = .systemFont(ofSize: 10)
        sizeField.textColor = .tertiaryLabelColor

        let stack = NSStackView(views: [titleField, dateField, sizeField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        cell.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])

        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 && row < snapshots.count else { return }
        let snap = snapshots[row]

        guard let doc = document,
              let sm = doc.snapshotManager else { return }

        if let content = try? sm.reconstructContent(at: snap.seq, currentContent: doc.content) {
            onSelect?(snap, content)
        }
    }

    @objc private func branchAction() {
        let row = tableView.selectedRow
        guard row >= 0 && row < snapshots.count else { return }
        let snap = snapshots[row]
        guard let doc = document,
              let sm = doc.snapshotManager,
              let content = try? sm.reconstructContent(at: snap.seq, currentContent: doc.content) else { return }
        onBranchFromHere?(snap, content)
    }

    private func typeLabel(_ type: String) -> String {
        switch type {
        case "manualSave":       return "Manual Save"
        case "autoSave":         return "Auto Save"
        case "sessionBoundary":  return "Session Boundary"
        case "forkPoint":        return "Fork Point"
        default:                 return type
        }
    }
}

// MARK: - Preview View Controller

public class HistoryPreviewViewController: NSViewController {
    private var textView: NSTextView!
    private var segmentedControl: NSSegmentedControl!
    private var currentSnapshot: SnapshotSummary?
    private var reconstructedContent: String = ""
    private var currentDocContent: String = ""
    private var showingDiff = false

    public override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))

        segmentedControl = NSSegmentedControl(labels: ["Content", "Diff"], trackingMode: .selectOne,
                                              target: self, action: #selector(toggleView))
        segmentedControl.selectedSegment = 0
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentSize = NSSize(width: 580, height: 560)
        textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.isEditable = false
        textView.isRichText = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)

        scrollView.documentView = textView

        container.addSubview(segmentedControl)
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            segmentedControl.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            segmentedControl.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            scrollView.topAnchor.constraint(equalTo: segmentedControl.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        self.view = container
    }

    func showContent(_ content: String, snapshot: SnapshotSummary, currentContent: String) {
        self.reconstructedContent = content
        self.currentSnapshot = snapshot
        self.currentDocContent = currentContent
        updateDisplay()
    }

    @objc private func toggleView() {
        showingDiff = segmentedControl.selectedSegment == 1
        updateDisplay()
    }

    private func updateDisplay() {
        guard let textStorage = textView.textStorage else { return }
        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        if showingDiff {
            showDiffView(textStorage)
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ]
            textStorage.setAttributedString(NSAttributedString(string: reconstructedContent, attributes: attrs))
        }
    }

    private func showDiffView(_ storage: NSMutableAttributedString) {
        let dmp = DiffMatchPatch()
        let diffs = dmp.diffMain(text1: reconstructedContent, text2: currentDocContent)

        let result = NSMutableAttributedString()
        let baseFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        for diff in diffs {
            let attrs: [NSAttributedString.Key: Any]
            switch diff.operation {
            case .equal:
                attrs = [.font: baseFont, .foregroundColor: NSColor.labelColor]
            case .insert:
                attrs = [.font: baseFont,
                         .foregroundColor: NSColor.systemGreen,
                         .backgroundColor: NSColor.systemGreen.withAlphaComponent(0.15)]
            case .delete:
                attrs = [.font: baseFont,
                         .foregroundColor: NSColor.systemRed,
                         .backgroundColor: NSColor.systemRed.withAlphaComponent(0.15),
                         .strikethroughStyle: NSUnderlineStyle.single.rawValue]
            }
            result.append(NSAttributedString(string: diff.text, attributes: attrs))
        }

        storage.setAttributedString(result)
    }
}
