import Foundation

public class AppleIntelligenceService: AIService {
    public init() {}
    public var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            return true
        }
        #endif
        return false
    }

    public var modelName: String { "Apple Intelligence" }

    public func rewrite(text: String, style: RewriteStyle) async throws -> String {
        throw AIError.unavailable
    }

    public func summarize(text: String, maxLength: Int?) async throws -> String {
        throw AIError.unavailable
    }

    public func write(prompt: String, context: String?) async throws -> String {
        throw AIError.unavailable
    }
}
