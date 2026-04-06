import Foundation

public enum RewriteStyle: String, CaseIterable {
    case professional = "Professional"
    case casual      = "Casual"
    case concise     = "Concise"
    case detailed    = "Detailed"
    case friendly    = "Friendly"
}

public protocol AIService {
    func rewrite(text: String, style: RewriteStyle) async throws -> String
    func summarize(text: String, maxLength: Int?) async throws -> String
    func write(prompt: String, context: String?) async throws -> String
    var isAvailable: Bool { get }
    var modelName: String { get }
}

public enum AIError: Error, LocalizedError {
    case unavailable
    case modelNotLoaded
    case generationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:              return "AI service is not available"
        case .modelNotLoaded:           return "No model is loaded"
        case .generationFailed(let m):  return "Generation failed: \(m)"
        }
    }
}
