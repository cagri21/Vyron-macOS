import Foundation
import VyronLocalization

public enum VyronImageTextError: Error, LocalizedError, Sendable, Equatable {
    case noText
    case recognitionFailed
    case textTooLong

    public var errorDescription: String? {
        switch self {
        case .noText:
            VyronModelDomainText.ocrNoText
        case .recognitionFailed:
            VyronModelDomainText.ocrRecognitionFailed
        case .textTooLong:
            VyronModelDomainText.ocrTextTooLong
        }
    }
}
