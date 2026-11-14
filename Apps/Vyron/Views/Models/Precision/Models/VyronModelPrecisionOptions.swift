import Foundation
import VyronModelData

struct VyronModelPrecisionOptions {
    let original: VyronOllamaInstalledModelIdentity
    let variants: [ModelSourceVariant]
    let connectionRevision: UUID
    let installedVariantIDs: Set<String>
}
