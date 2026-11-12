import Foundation
import VyronModelDomain

public struct VyronDeepSeekModelBudget: Sendable {
    public let contextTokens: Int
    public let maximumOutputTokens: Int

    // The model catalog publishes the same limits for Flash and V4 Pro.
    private static let current = Self(contextTokens: 1_048_576, maximumOutputTokens: 393_216)
    static let developmentMessages = VyronDevelopmentMessageBudget(workingBytes: 98_304, maximumBytes: 131_072)

    public static func published(for connection: ModelConnectionProfile, model: String? = nil) -> Self? {
        guard VyronDeepSeekRoute.matches(connection) else { return nil }
        switch (model ?? connection.selectedModel).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case VyronDeepSeekRoute.defaultModel, "deepseek-v4-pro", "deepseek-v4-flash", "deepseek-v4-flash-vision-exp":
            return current
        default:
            return nil
        }
    }
}
