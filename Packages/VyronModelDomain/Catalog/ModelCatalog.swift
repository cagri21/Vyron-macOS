import Foundation
import VyronLocalization

/// Curated local model tags. Download sizes are publisher estimates, not runtime-memory measurements.
public enum ModelCatalog {
    public static let recommendedCodingTag = "qwen3.8:27b"

    public static let all: [ModelDescriptor] = [
        ModelDescriptor(
            identity: .init(tag: "qwen3.8:27b", displayName: "Qwen3.8 27B", downloadSizeGB: 18),
            guidance: .init(
                summary: "Newer coding and reasoning model; recommended to try locally.",
                memoryNote: "Start with one loaded model and a 32K context."
            ),
            selection: .init(role: .coding, automatic: true, priority: 500),
            supportsThinking: true
        ),
        ModelDescriptor(
            identity: .init(tag: "qwen3.6:35b", displayName: "Qwen3.6 35B", downloadSizeGB: 23),
            guidance: .init(
                summary: "Mixture-of-experts alternative for coding and reasoning.",
                memoryNote: "23 GB weights; keep a 32K context and one model loaded."
            ),
            selection: .init(role: .coding, automatic: true, priority: 400),
            supportsThinking: true
        ),
        ModelDescriptor(
            identity: .init(tag: "devstral-small-2:24b", displayName: "Devstral Small 2 24B", downloadSizeGB: 15),
            guidance: .init(
                summary: "Software engineering model for repository exploration and editing.",
                memoryNote: "15 GB weights; a smaller download among the coding options."
            ),
            selection: .init(role: .coding, automatic: true, priority: 300),
            supportsThinking: false
        ),
        ModelDescriptor(
            identity: .init(tag: "qwen3-coder:30b", displayName: "Qwen3-Coder 30B", downloadSizeGB: 19),
            guidance: .init(
                summary: "The coding baseline used for the app's initial build-and-repair proof.",
                memoryNote: "19 GB weights; start with a 32K context."
            ),
            selection: .init(role: .coding, automatic: true, priority: 200),
            supportsThinking: false
        ),
        ModelDescriptor(
            identity: .init(tag: "qwen3-coder-next:q4_K_M", displayName: "Qwen3-Coder-Next Q4", downloadSizeGB: 52),
            guidance: .init(
                summary: "Large agentic coding model. Optional, explicit selection only.",
                memoryNote: "52 GB weights leave little headroom on a 64 GB Mac. Excluded from Auto."
            ),
            selection: .init(role: .coding, automatic: false, priority: 100, context: 8_192),
            supportsThinking: false
        ),
        ModelDescriptor(
            identity: .init(tag: "qwen3:4b", displayName: "Qwen3 4B", downloadSizeGB: 2.5),
            guidance: .init(
                summary: "Lightweight intent routing and chat helper; not a development model.",
                memoryNote: "2.5 GB download. Kept separate from coding-model selection."
            ),
            selection: .init(role: .helper, automatic: false, priority: 0, context: 16_384),
            supportsThinking: true
        )
    ]

    public static func descriptor(for tag: String) -> ModelDescriptor? {
        var name = withoutLibraryNamespace(tag).lowercased()
        // Metadata aliases only: the actual installed name is retained for every request.
        let defaults = [
            "qwen3.8": "qwen3.8:27b", "qwen3.6": "qwen3.6:35b", "devstral-small-2": "devstral-small-2:24b",
            "qwen3-coder": "qwen3-coder:30b", "qwen3-coder-next": "qwen3-coder-next:q4_k_m"
        ]
        let family = name.hasSuffix(":latest") ? String(name.dropLast(":latest".count)) : name
        if let canonical = defaults[family] { name = canonical }
        return all.first { $0.tag.lowercased() == name }
    }

    public static func codingIncompatibilityReason(for model: LocalModel) -> String? {
        guard VyronLocalModelTag.isValid(model.name) else {
            return VyronModelDomainText.catalogLocalTagsOnly
        }
        let descriptor = descriptor(for: model.name)
        if descriptor?.role == .helper {
            return VyronModelDomainText.catalogModelReservedForChat
        }
        if let capabilities = model.capabilities, !capabilities.isEmpty {
            guard capabilities.map({ $0.lowercased() }).contains("tools") else {
                return VyronModelDomainText.catalogNativeToolsUnavailable
            }
        } else if descriptor?.supportsTools != true {
            return VyronModelDomainText.catalogNativeToolsUnverified
        }
        return nil
    }

    static func isAutomaticCandidate(_ model: LocalModel) -> Bool {
        if model.size >= 40_000_000_000 { return false }
        if let descriptor = descriptor(for: model.name), descriptor.role == .coding {
            return descriptor.isAutomaticCodingCandidate
        }
        return true
    }

    package static func sameInstalledName(_ first: String, _ second: String) -> Bool {
        func normalized(_ name: String) -> String {
            let name = withoutLibraryNamespace(name)
            return name.contains(":") ? name : name + ":latest"
        }
        return normalized(first) == normalized(second)
    }

    private static func withoutLibraryNamespace(_ name: String) -> String {
        name.hasPrefix("library/") ? String(name.dropFirst("library/".count)) : name
    }

}
