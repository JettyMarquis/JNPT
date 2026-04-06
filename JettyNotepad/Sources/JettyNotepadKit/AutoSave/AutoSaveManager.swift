import AppKit

public class AutoSaveManager {
    public weak var document: JNTDocument?
    private var timer: Timer?
    private var idleTimer: Timer?

    public init() {}

    public func start(interval: TimeInterval = 60) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.triggerAutoSave()
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        idleTimer?.invalidate()
        idleTimer = nil
    }

    public func documentDidLoseFocus() {
        triggerAutoSave()
    }

    public func documentContentDidChange() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            self?.triggerAutoSave()
        }
    }

    private func triggerAutoSave() {
        guard let doc = document, doc.content != doc.lastSavedContent else { return }
        doc.autosave(withImplicitCancellability: false) { _ in }
    }
}
