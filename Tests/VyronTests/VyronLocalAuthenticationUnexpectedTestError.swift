import Foundation

struct VyronLocalAuthenticationUnexpectedTestError: LocalizedError {
    var errorDescription: String? { "fixture-private-key must never reach status" }
}
