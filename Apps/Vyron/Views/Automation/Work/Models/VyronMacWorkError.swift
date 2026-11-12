import Foundation

struct VyronMacWorkError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
