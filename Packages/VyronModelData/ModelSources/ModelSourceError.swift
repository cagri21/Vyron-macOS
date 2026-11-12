import Foundation
import VyronLocalization

public enum ModelSourceError: Error, LocalizedError, Sendable, Equatable {
    case invalidURL
    case unsupportedSource
    case noVariants
    case httpStatus(Int)
    case invalidMetadata
    case metadataTooLarge
    case invalidGGUF
    case splitGGUF
    case invalidLocalEndpoint
    case importFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return VyronModelDataText.sourceInvalidURL
        case .unsupportedSource:
            return VyronModelDataText.sourceUnsupported
        case .noVariants:
            return
                VyronModelDataText.sourceNoVariants
        case .httpStatus(let status):
            return
                VyronModelDataText.sourceHTTPStatus(String(status))
        case .invalidMetadata: return VyronModelDataText.sourceInvalidMetadata
        case .metadataTooLarge:
            return VyronModelDataText.sourceMetadataTooLarge
        case .invalidGGUF:
            return
                VyronModelDataText.sourceInvalidGGUF
        case .splitGGUF:
            return
                VyronModelDataText.sourceSplitGGUF
        case .invalidLocalEndpoint: return VyronModelDataText.sourceInvalidLocalEndpoint
        case .importFailed(let message): return VyronModelDataText.sourceImportFailed(message)
        }
    }
}
