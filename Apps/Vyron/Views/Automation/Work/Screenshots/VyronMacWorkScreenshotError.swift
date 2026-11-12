import Foundation

struct VyronMacWorkScreenshotError: Error, LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}
