import Foundation
import VyronModelData

struct VyronModelPrecisionChange: Sendable, Equatable {
    let original: VyronOllamaInstalledModelIdentity
    let replacement: ModelSourceVariant
    let connectionRevision: UUID
    let mayDownloadReplacement: Bool
}
