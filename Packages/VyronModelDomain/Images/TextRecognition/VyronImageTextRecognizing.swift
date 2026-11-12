import Foundation

/// Extracts visible text locally without interpreting it as a request to perform an action.
public protocol VyronImageTextRecognizing: Sendable {
    func recognizeText(in image: VyronImageAttachment) async throws -> String
}
