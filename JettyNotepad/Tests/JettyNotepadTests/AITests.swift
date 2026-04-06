import Foundation
import JettyNotepadKit

func runAITests() {
    print("\n--- AI Service Tests ---")

    test("AIManager: default provider is disabled") {
        let manager = AIManager.shared
        try assertEqual(manager.activeProvider, .disabled)
    }

    test("AIManager: disabled provider → activeService is nil") {
        let manager = AIManager.shared
        manager.activeProvider = .disabled
        try assertTrue(manager.activeService == nil)
    }

    test("AIManager: localModel without path → activeService is nil") {
        let manager = AIManager.shared
        manager.activeProvider = .localModel
        manager.localModel.modelPath = nil
        try assertTrue(manager.activeService == nil, "No path → not available")
        // Restore
        manager.activeProvider = .disabled
    }

    test("AIManager: localModel with path → activeService is non-nil") {
        let manager = AIManager.shared
        manager.activeProvider = .localModel
        manager.localModel.modelPath = "/tmp/fake.gguf"
        try assertNotNil(manager.activeService)
        // Restore
        manager.activeProvider = .disabled
        manager.localModel.modelPath = nil
    }

    test("AppleIntelligenceService: isAvailable reflects FoundationModels presence") {
        let svc = AppleIntelligenceService()
        #if canImport(FoundationModels)
        try assertTrue(svc.isAvailable, "FoundationModels available — service should be available")
        #else
        try assertTrue(!svc.isAvailable, "FoundationModels not available — service should not be available")
        #endif
    }

    test("LocalModelService: without model path, rewrite throws modelNotLoaded") {
        let svc = LocalModelService()
        svc.modelPath = nil
        var threw = false
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                _ = try await svc.rewrite(text: "hello", style: .casual)
            } catch AIError.modelNotLoaded {
                threw = true
            } catch {}
            sem.signal()
        }
        sem.wait()
        try assertTrue(threw, "Expected modelNotLoaded error")
    }

    test("LocalModelService: with path, rewrite throws generationFailed") {
        let svc = LocalModelService()
        svc.modelPath = "/tmp/fake.gguf"
        var threw = false
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                _ = try await svc.rewrite(text: "hello", style: .professional)
            } catch AIError.generationFailed {
                threw = true
            } catch {}
            sem.signal()
        }
        sem.wait()
        try assertTrue(threw, "Expected generationFailed error")
    }

    test("RewriteStyle: all cases have non-empty rawValue") {
        for style in RewriteStyle.allCases {
            try assertTrue(!style.rawValue.isEmpty, "Style \(style) has empty rawValue")
        }
    }

    test("RewriteStyle: has 5 cases") {
        try assertEqual(RewriteStyle.allCases.count, 5)
    }

    test("AIProvider: has 3 cases") {
        try assertEqual(AIProvider.allCases.count, 3)
    }

    test("AIError: localizedDescriptions are non-empty") {
        let errors: [AIError] = [.unavailable, .modelNotLoaded, .generationFailed("test")]
        for e in errors {
            try assertNotNil(e.errorDescription)
            try assertTrue(!(e.errorDescription ?? "").isEmpty)
        }
    }
}
