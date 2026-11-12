import Foundation
import VyronModelDomain

/// Known OpenAI model families that need Responses for reasoning with native tools.
/// Other models and compatible servers retain their established transport.
enum VyronOpenAIResponsesRoute {
    static let endpoint = "https://api.openai.com/v1"

    static func matches(_ profile: ModelConnectionProfile) -> Bool {
        guard profile.kind == .openAICompatible,
            let endpoint = URLComponents(string: profile.endpoint),
            endpoint.scheme == "https",
            endpoint.host == "api.openai.com",
            endpoint.port == nil || endpoint.port == 443,
            endpoint.path == "/v1"
        else { return false }

        return modelFamily(for: profile.selectedModel) != nil
    }

    static func modelFamily(for model: String) -> VyronOpenAIResponsesModelFamily? {
        VyronOpenAIResponsesModelFamily.allCases.first { family in
            let name = family.rawValue
            return model == name
                || (model.hasPrefix(name + "-")
                    && isSnapshotDate(String(model.dropFirst(name.count + 1))))
        }
    }

    private static func isSnapshotDate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
            parts.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
            let month = Int(parts[1]), let day = Int(parts[2])
        else { return false }
        return (1...12).contains(month) && (1...31).contains(day)
    }
}
