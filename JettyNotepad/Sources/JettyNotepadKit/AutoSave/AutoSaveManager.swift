import AppKit

public enum AutoSavePrefKeys {
    public static let interval = "autoSaveInterval"
}

public class AutoSaveManager {
    public weak var document: JNTDocument?
    private var timer: Timer?
    private var idleTimer: Timer?

    public var hasScheduledPeriodicTimer: Bool { timer != nil }

    public init() {}

    /// Reads the user's configured interval: unset (`object(forKey:) == nil`) means
    /// the pref was never touched → 60s default; an explicit `0.0` means the user
    /// picked "Off" in Preferences. These must be distinguished since
    /// `UserDefaults.double(forKey:)` returns 0.0 for both.
    public static func configuredInterval(defaults: UserDefaults = .standard) -> TimeInterval {
        guard defaults.object(forKey: AutoSavePrefKeys.interval) != nil else { return 60 }
        return defaults.double(forKey: AutoSavePrefKeys.interval)
    }

    /// interval <= 0 ("Off") means: don't schedule periodic autosave. This does NOT
    /// disable idle (5s after typing stops) or focus-loss autosave — those remain
    /// on as a last line of defense against losing edits; only the periodic timer
    /// is user-configurable in this MVP.
    public func start(interval: TimeInterval = 60) {
        stop()
        guard interval > 0 else { return }
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
