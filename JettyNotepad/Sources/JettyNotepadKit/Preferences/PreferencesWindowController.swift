import AppKit
import SwiftUI

public class PreferencesWindowController: NSWindowController {
    public convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
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

struct PreferencesView: View {
    @AppStorage(AutoSavePrefKeys.interval) private var autoSaveInterval: Double = 60
    @AppStorage("newFileOpensIn")   private var newFileOpensIn: Int = 0

    var body: some View {
        Form {
            Section("Auto-Save") {
                Picker("Interval:", selection: $autoSaveInterval) {
                    Text("30 seconds").tag(30.0)
                    Text("1 minute").tag(60.0)
                    Text("2 minutes").tag(120.0)
                    Text("5 minutes").tag(300.0)
                    Text("Off (idle & focus-loss saves still apply)").tag(0.0)
                }
                .pickerStyle(.menu)
                Text("Changes take effect the next time a document is opened.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("New Documents") {
                Picker("Open in:", selection: $newFileOpensIn) {
                    Text("New Tab").tag(0)
                    Text("New Window").tag(1)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(20)
        .frame(width: 340, height: 140)
    }
}
