import Foundation
@testable import VyronCore
@testable import VyronModelData

actor VyronOllamaOCRTestRecognizer: VyronImageTextRecognizing {
    private var text: String
    private var shouldFail: Bool
    private let waitsForCancellation: Bool
    private(set) var calls = 0

    init(text: String, shouldFail: Bool = false, waitsForCancellation: Bool = false) {
        self.text = text
        self.shouldFail = shouldFail
        self.waitsForCancellation = waitsForCancellation
    }

    func recognizeText(in image: VyronImageAttachment) async throws -> String {
        calls += 1
        if waitsForCancellation { try await Task.sleep(for: .seconds(30)) }
        try Task.checkCancellation()
        if shouldFail { throw VyronImageTextError.recognitionFailed }
        return text
    }

    func recover(with text: String) {
        self.text = text
        shouldFail = false
    }
}
