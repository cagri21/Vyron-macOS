import Foundation
import VyronCore

enum VyronScreenshotErrorPresentation {
    static func description(_ error: any Error) -> String {
        if error is VyronImageTextRecognitionFailure { return VyronScreenshotText.textRecognitionFailed }
        if let textError = error as? VyronImageTextError {
            switch textError {
            case .noText: return VyronScreenshotText.noReadableText
            case .recognitionFailed: return VyronScreenshotText.textRecognitionFailed
            case .textTooLong: return VyronScreenshotText.extractedTextTooLong
            }
        }
        guard let imageError = error as? VyronImageAttachmentError else { return error.localizedDescription }
        switch imageError {
        case .invalidRole: return VyronScreenshotText.invalidRole
        case .tooManyImages: return VyronScreenshotText.tooManyImages
        case .invalidSize: return VyronScreenshotText.invalidSize
        case .requestTooLarge: return VyronScreenshotText.requestTooLarge
        case .unsupportedFormat: return VyronScreenshotText.unsupportedFormat
        case .visionUnsupported: return VyronScreenshotText.visionUnsupported
        }
    }
}
