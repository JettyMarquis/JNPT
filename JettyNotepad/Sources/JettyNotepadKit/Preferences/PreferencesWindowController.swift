import AppKit
import SwiftUI

/// Basic preferences window — SwiftUI content hosted in NSHostingView.
public class PreferencesWindowController: NSWindowController {
    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.center()

        let hostingView = NSHostingView(rootView: PreferencesView())
        window.contentView = hostingView

        self.init(window: window)
    }
}

// MARK: - SwiftUI Preferences View

struct PreferencesView: View {
    @State private var autoSaveInterval: Double = 60
    @State private var newFileOpensIn: Int = 0  // 0 = tab, 1 = window
    @State private var storageUsed: String = "Calculating..."
    @State private var orphanRetentionDays: String = "90"
    @State private var maxCapacityMB: String = ""

    @AppStorage("markdownDefaultEnabled") private var markdownDefaultEnabled = false
    @AppStorage("spellCheckEnabled")      private var spellCheckEnabled      = false
    @AppStorage("autoCorrectEnabled")     private var autoCorrectEnabled     = false
    @AppStorage("grammarCheckEnabled")    private var grammarCheckEnabled    = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gear") }
            historyTab
                .tabItem { Label("History", systemImage: "clock") }
            editorTab
                .tabItem { Label("Editor", systemImage: "pencil") }
        }
        .padding(20)
        .frame(width: 430, height: 360)
    }

    private var editorTab: some View {
        Form {
            Section("Markdown") {
                Toggle("Enable Markdown rendering for new documents",
                       isOn: $markdownDefaultEnabled)
            }
            Section("Spelling") {
                Toggle("Check spelling while typing",     isOn: $spellCheckEnabled)
                Toggle("Correct spelling automatically",  isOn: $autoCorrectEnabled)
                Toggle("Check grammar with spelling",     isOn: $grammarCheckEnabled)
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section("Auto-Save") {
                Picker("Interval:", selection: $autoSaveInterval) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("Off").tag(0.0)
                }
                .pickerStyle(.menu)
            }

            Section("New Documents") {
                Picker("Open in:", selection: $newFileOpensIn) {
                    Text("New Tab").tag(0)
                    Text("New Window").tag(1)
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var historyTab: some View {
        Form {
            Section("JettyNote Folder") {
                HStack {
                    Text(ExternalFileManager.jettyNoteFolder.path)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            }

            Section("Storage") {
                HStack {
                    Text("Used:")
                    Text(storageUsed)
                        .foregroundColor(.secondary)
                }
                .onAppear { updateStorageInfo() }
            }

            Section("Cleanup") {
                HStack {
                    Text("Orphan retention (days):")
                    TextField("90", text: $orphanRetentionDays)
                        .frame(width: 60)
                }
                HStack {
                    Text("Max capacity (MB):")
                    TextField("Unlimited", text: $maxCapacityMB)
                        .frame(width: 80)
                }

                HStack(spacing: 12) {
                    Button("Scan for Orphans") { scanOrphans() }
                    Button("Clean Up...") { cleanup() }
                    Button("Clear All History...") { clearAll() }
                        .foregroundColor(.red)
                }
            }
        }
    }

    private func updateStorageInfo() {
        DispatchQueue.global().async {
            let bytes = (try? CleanupManager.totalStorageBytes()) ?? 0
            let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            DispatchQueue.main.async {
                storageUsed = formatted
            }
        }
    }

    private func scanOrphans() {
        DispatchQueue.global().async {
            if let orphans = try? CleanupManager.scanForOrphans() {
                try? CleanupManager.moveToOrphans(orphans)
                DispatchQueue.main.async {
                    updateStorageInfo()
                }
            }
        }
    }

    private func cleanup() {
        DispatchQueue.global().async {
            let days = Int(orphanRetentionDays) ?? 90
            try? CleanupManager.purgeOldOrphans(olderThanDays: days)
            if let maxMB = Int(maxCapacityMB), maxMB > 0 {
                try? CleanupManager.cleanByCapacity(maxBytes: Int64(maxMB) * 1_000_000)
            }
            DispatchQueue.main.async { updateStorageInfo() }
        }
    }

    private func clearAll() {
        DispatchQueue.global().async {
            try? CleanupManager.clearAll()
            DispatchQueue.main.async { updateStorageInfo() }
        }
    }
}
