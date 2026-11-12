import Foundation
import VyronModelDomain

/// Capability inspection does not retrieve a key or contact any provider.
public enum VyronConnectionBalancePolicy {
    public static func support(for profile: ModelConnectionProfile) -> VyronConnectionBalanceSupport {
        let endpoint = profile.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, endpoint.utf8.count <= 2_048,
            !endpoint.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
            let parts = URLComponents(string: endpoint),
            let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(),
            parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil
        else { return .unsupported }
        if ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host), ["https", "http"].contains(scheme) {
            return .local
        }
        guard profile.kind == .openAICompatible, scheme == "https",
            parts.port == nil || parts.port == 443
        else { return .unsupported }
        let path = parts.percentEncodedPath
        switch host {
        case "api.deepseek.com":
            return ["", "/", "/v1", "/v1/"].contains(path) ? .deepSeek : .unsupported
        case "openrouter.ai":
            return ["/api/v1", "/api/v1/"].contains(path) ? .openRouter : .unsupported
        case "api.openai.com":
            return ["", "/", "/v1", "/v1/"].contains(path) ? .dashboardOnly : .unsupported
        default:
            return .unsupported
        }
    }
}
