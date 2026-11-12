import Foundation
import VyronCore
import XCTest
@testable import Vyron

@MainActor
final class VyronOCRPresentationTests: XCTestCase {
    func testTextOnlyOllamaExplainsLocalTextAndVisionKeepsImageHint() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = ModelConnectionProfile(
            name: "Local Qwen", kind: .ollama, endpoint: "http://localhost:11434",
            selectedModel: "qwen3-coder:30b"
        )
        test.select(profile, provider: test.provider, capabilities: ["completion", "tools"])
        XCTAssertEqual(test.model.screenshotAnalysisHint, VyronScreenshotText.localTextHint)

        test.model.modelSelection.models = [LocalModel(name: profile.selectedModel, size: 1, capabilities: ["vision", "tools"])]
        XCTAssertEqual(test.model.screenshotAnalysisHint, VyronScreenshotText.analysisHint)
    }

    func testUnknownBuiltinModelOffersLocalTextWithoutChangingModeOrSelection() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.model.modelSelection.activeConnectionID = nil
        test.model.composer.mode = .plan
        let modelName = test.model.modelSelection.selectedModel
        XCTAssertEqual(test.model.screenshotAnalysisHint, VyronScreenshotText.localTextHint)
        XCTAssertEqual(test.model.modelSelection.selectedModel, modelName)
        XCTAssertEqual(test.model.composer.mode, .plan)
    }

    func testCompatibleTextOnlyModelDoesNotPromiseOllamaFallback() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        test.select(test.profile(), provider: test.provider, capabilities: ["completion", "tools"])
        XCTAssertEqual(test.model.screenshotAnalysisHint, VyronScreenshotText.visionRequired)
    }

    func testOCRFailuresHaveLocalizedRecoveryMessages() {
        XCTAssertEqual(
            VyronScreenshotErrorPresentation.description(VyronImageTextRecognitionFailure(
                error: NSError(domain: "VisionTest", code: 7)
            )),
            VyronScreenshotText.textRecognitionFailed
        )
        XCTAssertEqual(
            VyronScreenshotErrorPresentation.description(VyronImageTextError.noText),
            VyronScreenshotText.noReadableText
        )
        XCTAssertEqual(
            VyronScreenshotErrorPresentation.description(VyronImageTextError.recognitionFailed),
            VyronScreenshotText.textRecognitionFailed
        )
        XCTAssertEqual(
            VyronScreenshotErrorPresentation.description(VyronImageTextError.textTooLong),
            VyronScreenshotText.extractedTextTooLong
        )
    }
}
