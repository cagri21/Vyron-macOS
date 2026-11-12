import VyronModelDomain

enum VyronOllamaProgressStatus {
    static let success = "success"

    static func phase(for status: String) -> VyronModelPullPhase {
        let normalized = status.lowercased()
        if normalized == success { return .modelFilesReady }
        if normalized.hasPrefix("pulling") {
            return normalized.contains("manifest") ? .findingModelFiles : .downloadingModelFiles
        }
        if normalized.hasPrefix("verifying") { return .checkingFiles }
        return .finishingSetup
    }
}
