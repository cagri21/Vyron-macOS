import Foundation
import VyronModelDomain

public enum ModelEndpoint {
    public static func validated(_ endpoint: String, kind: ModelProviderKind) throws -> URL {
        let value = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= VyronModelEndpointPolicy.maximumEndpointCharacters,
            !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
            var parts = URLComponents(string: value),
            let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(), !host.isEmpty,
            parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
            parts.port.map(VyronModelEndpointPolicy.validPorts.contains) ?? true,
            scheme == VyronModelEndpointPolicy.secureScheme
                || (scheme == VyronModelEndpointPolicy.insecureScheme
                    && VyronModelEndpointPolicy.loopbackHosts.contains(host)),
            !parts.percentEncodedPath.lowercased().contains("%2f"),
            !parts.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
        else { throw ModelProviderError.invalidEndpoint }
        parts.scheme = scheme
        parts.host = host
        while parts.path.hasSuffix("/") { parts.path.removeLast() }
        if kind != .ollama, parts.path.isEmpty { parts.path = VyronModelEndpointPolicy.compatibleBasePath }
        if kind == .ollama, parts.path.hasSuffix(VyronModelEndpointPolicy.ollamaAPIPath) {
            parts.path.removeLast(VyronModelEndpointPolicy.ollamaAPIPath.count)
        }
        guard let url = parts.url else { throw ModelProviderError.invalidEndpoint }
        return url
    }

    static func matchesOfficialCompatibleEndpoint(_ endpoint: String, profile: ModelConnectionProfile) -> Bool {
        guard profile.kind == .openAICompatible,
            let url = try? validated(profile.endpoint, kind: profile.kind),
            url.port == nil || url.port == 443,
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        parts.port = nil
        return parts.string == endpoint
    }

    public static func validateModelID(_ model: String) throws {
        guard !model.isEmpty, model.utf8.count <= VyronModelEndpointPolicy.maximumModelIDBytes,
            !model.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
            })
        else { throw ModelProviderError.invalidModel }
    }
}
