import Foundation

struct VyronDevelopmentTaskStateError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
