import Foundation

public enum AIProvider: String, CaseIterable {
    case appleIntelligence = "Apple Intelligence"
    case localModel        = "Local Model"
    case disabled          = "Disabled"
}

public class AIManager {
    public static let shared = AIManager()

    public let appleIntelligence = AppleIntelligenceService()
    public let localModel        = LocalModelService()

    public var activeProvider: AIProvider = .disabled

    public var activeService: (any AIService)? {
        switch activeProvider {
        case .appleIntelligence: return appleIntelligence.isAvailable ? appleIntelligence : nil
        case .localModel:        return localModel.isAvailable        ? localModel        : nil
        case .disabled:          return nil
        }
    }

    private init() {}
}
