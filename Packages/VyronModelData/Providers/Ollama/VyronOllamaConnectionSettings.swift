import Foundation
import VyronModelDomain

struct VyronOllamaConnectionSettings {
    let isConfigured: Bool
    let model: ModelSettings
    let apiKey: String?
}
