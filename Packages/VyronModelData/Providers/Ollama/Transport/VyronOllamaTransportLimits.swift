import Foundation

enum VyronOllamaTransportLimits {
    static let metadataTimeout: TimeInterval = 10
    static let structuredInferenceTimeout: TimeInterval = 180
    static let maximumMetadataBytes = 4_194_304
    static let maximumCatalogBytes = 8_388_608
    static let maximumStreamLineBytes = 2_097_152
    static let maximumErrorBodyBytes = 4_096
}
