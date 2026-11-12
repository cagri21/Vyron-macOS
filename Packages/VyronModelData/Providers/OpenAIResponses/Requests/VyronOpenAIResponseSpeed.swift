import Foundation
import VyronModelDomain

/// Provider wire values stay at the adapter boundary. Standard explicitly overrides project-level Fast defaults.
enum VyronOpenAIResponseSpeed {
    static func serviceTier(settings: ModelSettings, model: String) -> String {
        let supported = VyronOpenAIPriceCatalog.pricing(for: model)?.serviceMultiplier("fast") != nil
        return settings.responseSpeed == .fast && supported ? "fast" : "default"
    }
}
