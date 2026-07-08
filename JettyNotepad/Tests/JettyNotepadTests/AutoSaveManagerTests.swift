import Foundation
import JettyNotepadKit

func runAutoSaveManagerTests() {
    print("\nAutoSaveManagerTests:")

    func isolatedDefaults() -> (UserDefaults, () -> Void) {
        let suite = "jnpt.test.autosave.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (defaults, { defaults.removePersistentDomain(forName: suite) })
    }

    test("configuredInterval defaults to 60 when unset") {
        let (defaults, cleanup) = isolatedDefaults()
        defer { cleanup() }
        try assertEqual(AutoSaveManager.configuredInterval(defaults: defaults), 60)
    }

    test("configuredInterval distinguishes explicit Off (0.0) from unset") {
        let (defaults, cleanup) = isolatedDefaults()
        defer { cleanup() }
        defaults.set(0.0, forKey: AutoSavePrefKeys.interval)
        try assertEqual(AutoSaveManager.configuredInterval(defaults: defaults), 0)
    }

    test("configuredInterval reads an explicit non-default value") {
        let (defaults, cleanup) = isolatedDefaults()
        defer { cleanup() }
        defaults.set(300.0, forKey: AutoSavePrefKeys.interval)
        try assertEqual(AutoSaveManager.configuredInterval(defaults: defaults), 300)
    }

    test("start(interval: 0) does not schedule a periodic timer (Off)") {
        let mgr = AutoSaveManager()
        mgr.start(interval: 0)
        try assertTrue(!mgr.hasScheduledPeriodicTimer)
    }

    test("start(interval: >0) schedules a periodic timer; stop() clears it") {
        let mgr = AutoSaveManager()
        mgr.start(interval: 30)
        try assertTrue(mgr.hasScheduledPeriodicTimer)
        mgr.stop()
        try assertTrue(!mgr.hasScheduledPeriodicTimer)
    }

    test("calling start() again does not leak the previous timer") {
        let mgr = AutoSaveManager()
        mgr.start(interval: 30)
        mgr.start(interval: 60)
        try assertTrue(mgr.hasScheduledPeriodicTimer)
        mgr.stop()
        try assertTrue(!mgr.hasScheduledPeriodicTimer)
    }
}
