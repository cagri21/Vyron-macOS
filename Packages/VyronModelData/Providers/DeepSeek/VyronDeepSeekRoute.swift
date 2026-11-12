import Foundation
import VyronModelDomain

/// The official DeepSeek transport; a similarly named model on another server has its own capabilities.
public enum VyronDeepSeekRoute {
    public static let endpoint = "https://api.deepseek.com/v1"
    public static let defaultModel = "deepseek-flash"
    public static let models = [defaultModel, "deepseek-v4-pro"]

    public static func matches(_ profile: ModelConnectionProfile) -> Bool {
        guard profile.kind == .openAICompatible,
            let url = URL(string: profile.endpoint), url.scheme?.lowercased() == "https",
            url.host?.lowercased() == "api.deepseek.com", url.port == nil || url.port == 443,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return false }
        return ["", "/", "/v1", "/v1/"].contains(url.path)
    }

    public static func thinkingSupport(for model: String) -> VyronModelThinkingSupport {
        thinkingModels.contains(model.lowercased()) ? .boolean : .unverified
    }

    private static let thinkingModels: Set<String> = [
        "deepseek-flash", "deepseek-v4-flash", "deepseek-v4-flash-vision-exp", "deepseek-v4-pro",
        "deepseek-chat", "deepseek-reasoner", "deepseek-v4.1-flash-1017", "deepseek-v4-pro-0813"
    ]
}
