import Foundation
@testable import VyronCore

actor VyronImageTextTestRecognizer: VyronImageTextRecognizing {
    private let response: @Sendable (VyronImageAttachment, Int) async throws -> String
    private(set) var receivedImages: [VyronImageAttachment] = []

    init(response: @escaping @Sendable (VyronImageAttachment, Int) async throws -> String) {
        self.response = response
    }

    func recognizeText(in image: VyronImageAttachment) async throws -> String {
        receivedImages.append(image)
        return try await response(image, receivedImages.count)
    }
}
