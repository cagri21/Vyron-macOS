import Foundation

enum VyronModelSourceLimits {
    static let requestTimeout: TimeInterval = 60
    static let resourceTimeout: TimeInterval = 86_400
    static let discoveryTimeout: TimeInterval = 20
    static let installedCatalogTimeout: TimeInterval = 15
    static let transferTimeout: TimeInterval = 3_600
    static let maximumMetadataBytes = 8_388_608
    static let maximumImportResponseBytes = 1_048_576
    static let digestChunkBytes = 1_048_576
    static let maximumVariants = 10_000
}
