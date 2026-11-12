import Foundation

enum VyronScreenshotImportError: LocalizedError {
    case invalidImage
    case tooLarge

    var errorDescription: String? {
        switch self {
        case .invalidImage: VyronScreenshotText.invalidImage
        case .tooLarge: VyronScreenshotText.imageTooLarge
        }
    }
}
