import AppKit
import SwiftUI

public class AIPanelController: NSWindowController {
    public convenience init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "AI Assistant"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.center()

        let hostingView = NSHostingView(rootView: AIPanelView())
        panel.contentView = hostingView

        self.init(window: panel)
    }
}

// MARK: - SwiftUI AI Panel View

struct AIPanelView: View {
    @State private var selectedTab = 0
    @State private var rewriteStyle: RewriteStyle = .professional
    @State private var previewText: String = ""
    @State private var promptText: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let aiManager = AIManager.shared

    var body: some View {
        VStack(spacing: 0) {
            providerStatus
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            Divider()
            TabView(selection: $selectedTab) {
                rewriteTab.tabItem { Text("Rewrite") }.tag(0)
                summarizeTab.tabItem { Text("Summarize") }.tag(1)
                writeTab.tabItem { Text("Write") }.tag(2)
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
    }

    // MARK: Provider status

    private var providerStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(aiManager.activeService != nil ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(aiManager.activeService?.modelName ?? "Disabled")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
    }

    // MARK: Rewrite tab

    private var rewriteTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Style:", selection: $rewriteStyle) {
                ForEach(RewriteStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .pickerStyle(.menu)

            Button(isLoading ? "Rewriting…" : "Rewrite") {
                runRewrite()
            }
            .disabled(isLoading || aiManager.activeService == nil)

            if !previewText.isEmpty {
                ScrollView {
                    Text(previewText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

                HStack {
                    Button("Accept") { insertAtCursor(previewText) }
                    Button("Revert") { previewText = "" }
                }
            }

            errorView
            Spacer()
        }
    }

    // MARK: Summarize tab

    private var summarizeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(isLoading ? "Summarizing…" : "Summarize") {
                runSummarize()
            }
            .disabled(isLoading || aiManager.activeService == nil)

            if !previewText.isEmpty {
                ScrollView {
                    Text(previewText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(6)

                Button("Open in New Document") { openInNewDocument(previewText) }
            }

            errorView
            Spacer()
        }
    }

    // MARK: Write tab

    private var writeTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Describe what to write…", text: $promptText)
                .textFieldStyle(.roundedBorder)

            Button(isLoading ? "Generating…" : "Generate") {
                runWrite()
            }
            .disabled(isLoading || promptText.isEmpty || aiManager.activeService == nil)

            errorView
            Spacer()
        }
    }

    // MARK: Error view

    @ViewBuilder
    private var errorView: some View {
        if let msg = errorMessage {
            Text(msg)
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    // MARK: AI calls

    private func runRewrite() {
        guard let service = aiManager.activeService,
              let doc = NSDocumentController.shared.currentDocument as? JNTDocument else { return }
        let text = doc.content
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await service.rewrite(text: text, style: rewriteStyle)
                await MainActor.run { previewText = result; isLoading = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
            }
        }
    }

    private func runSummarize() {
        guard let service = aiManager.activeService,
              let doc = NSDocumentController.shared.currentDocument as? JNTDocument else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await service.summarize(text: doc.content, maxLength: 300)
                await MainActor.run { previewText = result; isLoading = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
            }
        }
    }

    private func runWrite() {
        guard let service = aiManager.activeService,
              let doc = NSDocumentController.shared.currentDocument as? JNTDocument else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await service.write(prompt: promptText, context: doc.content)
                await MainActor.run { insertAtCursor(result); isLoading = false }
            } catch {
                await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
            }
        }
    }

    private func insertAtCursor(_ text: String) {
        guard let doc = NSDocumentController.shared.currentDocument as? JNTDocument,
              let editor = doc.editorViewController else { return }
        let tv: NSTextView = editor.textView
        let range = tv.selectedRange()
        tv.insertText(text, replacementRange: range)
    }

    private func openInNewDocument(_ text: String) {
        NSDocumentController.shared.newDocument(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if let doc = NSDocumentController.shared.currentDocument as? JNTDocument {
                doc.content = text
                doc.editorViewController?.textView.string = text
            }
        }
    }
}
