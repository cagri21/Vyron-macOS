import Foundation

struct VyronModelSettingsInputError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}
