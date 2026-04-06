import Foundation

public class LocalModelService: AIService {
    public var modelPath: String?
    public var temperature: Double = 0.7
    public var maxTokens: Int = 512

    public var isAvailable: Bool { modelPath != nil }
    public var modelName: String {
        modelPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No model loaded"
    }

    public init() {}

    public func rewrite(text: String, style: RewriteStyle) async throws -> String {
        guard isAvailable else { throw AIError.modelNotLoaded }
        // Placeholder: real implementation would call llama.cpp
        throw AIError.generationFailed("Local model integration not yet implemented")
    }

    public func summarize(text: String, maxLength: Int?) async throws -> String {
        guard isAvailable else { throw AIError.modelNotLoaded }
        throw AIError.generationFailed("Local model integration not yet implemented")
    }

    public func write(prompt: String, context: String?) async throws -> String {
        guard isAvailable else { throw AIError.modelNotLoaded }
        throw AIError.generationFailed("Local model integration not yet implemented")
    }
}
