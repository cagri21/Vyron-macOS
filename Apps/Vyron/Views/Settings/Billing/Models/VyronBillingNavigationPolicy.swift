import Foundation

enum VyronBillingNavigationPolicy {
    static func decision(for url: URL?, isMainFrame: Bool) -> VyronBillingNavigationDecision {
        guard let url else { return .block }
        if url.absoluteString == "about:blank" { return .allow }
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(),
            parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443 else { return .block }
        // Embedded resources remain subject to WebKit's origin policy. Top-level sign-in stays visibly on OpenAI.
        if !isMainFrame || host == "openai.com" || host.hasSuffix(".openai.com") { return .allow }
        return .browserRequired
    }
}
