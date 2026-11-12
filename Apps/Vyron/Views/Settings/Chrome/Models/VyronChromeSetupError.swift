import Foundation

enum VyronChromeSetupError: LocalizedError {
    case invalidExtensionID
    case missingHost
    case unsafePath

    var errorDescription: String? {
        switch self {
        case .invalidExtensionID: VyronChromeText.invalidID
        case .missingHost: VyronChromeText.missingHost
        case .unsafePath: VyronChromeText.unsafePath
        }
    }
}
