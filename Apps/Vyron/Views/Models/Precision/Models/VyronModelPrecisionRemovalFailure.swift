import Foundation

struct VyronModelPrecisionRemovalFailure: LocalizedError {
    let replacement: String
    let original: String
    let detail: String

    var errorDescription: String? {
        VyronAppText.settingsPrecisionRemovalFailed(replacement, original, detail)
    }
}
