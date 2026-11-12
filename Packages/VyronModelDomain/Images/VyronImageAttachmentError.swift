import Foundation
import VyronLocalization

public enum VyronImageAttachmentError: Error, LocalizedError, Sendable, Equatable {
    case invalidRole
    case tooManyImages
    case invalidSize
    case requestTooLarge
    case unsupportedFormat
    case visionUnsupported

    public var errorDescription: String? {
        let language = VyronResourceLanguage.selection
        let locale = Locale(identifier: language.resolved().rawValue)
        return switch self {
        case .invalidRole:
            VyronModelDomainText.imageInvalidRole
        case .tooManyImages:
            VyronModelDomainText.imageTooMany
        case .invalidSize:
            VyronModelDomainText.imageInvalidSize(
                (VyronImageAttachment.maximumDataBytes / VyronImageAttachment.bytesPerMebibyte)
                    .formatted(.number.locale(locale)),
                language: language
            )
        case .requestTooLarge:
            VyronModelDomainText.imageRequestTooLarge(
                (VyronImageAttachment.maximumRequestDataBytes / VyronImageAttachment.bytesPerMebibyte)
                    .formatted(.number.locale(locale)),
                language: language
            )
        case .unsupportedFormat:
            VyronModelDomainText.imageUnsupportedFormat
        case .visionUnsupported:
            VyronModelDomainText.imageVisionUnsupported
        }
    }
}
