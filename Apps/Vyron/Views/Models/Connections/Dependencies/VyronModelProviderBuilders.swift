import VyronModelData
import VyronModelDomain

struct VyronModelProviderBuilders {
    let builtin: @MainActor (ModelSettings) throws -> OllamaClient
    let configured: @MainActor (ModelConnectionProfile, String) throws -> any ModelProvider
    var autoLocal: VyronAutoLocalServices?
}
