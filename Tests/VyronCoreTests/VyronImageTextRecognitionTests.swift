import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronImageTextRecognitionTests: XCTestCase {
    func testAppleVisionReadsGeneratedScreenshotWithoutAProvider() async throws {
        let image = try VyronImageTextFixture.image(text: "VYRON OCR 7429")
        let text = try await VyronAppleVisionTextRecognizer().recognizeText(in: image)
        XCTAssertTrue(text.contains("VYRON"), text)
        XCTAssertTrue(text.contains("7429"), text)
    }

    func testAppleVisionReturnsNoTextForBlankScreenshot() async throws {
        let image = try VyronImageTextFixture.image(text: "")
        let text = try await VyronAppleVisionTextRecognizer().recognizeText(in: image)
        XCTAssertTrue(text.isEmpty)
    }

    func testRecognitionDiagnosticsKeepOnlyBoundedErrorDomainsAndCodes() {
        let privateContent = "private OCR image text must not appear in diagnostics"
        var source = NSError(domain: "fixture-7", code: 7, userInfo: [NSLocalizedDescriptionKey: privateContent])
        for index in (0..<7).reversed() {
            source = NSError(domain: "fixture-\(index)", code: index, userInfo: [
                NSLocalizedDescriptionKey: privateContent,
                "imageText": privateContent,
                NSUnderlyingErrorKey: source
            ])
        }
        let failure = VyronImageTextRecognitionFailure(error: source)
        XCTAssertEqual(failure.domain, "fixture-0")
        XCTAssertEqual(failure.code, 0)
        XCTAssertEqual(failure.underlying, [
            VyronImageTextFailureDiagnostic(domain: "fixture-1", code: 1),
            VyronImageTextFailureDiagnostic(domain: "fixture-2", code: 2),
            VyronImageTextFailureDiagnostic(domain: "fixture-3", code: 3)
        ])
        XCTAssertEqual(failure.errorDescription, VyronImageTextError.recognitionFailed.errorDescription)
        XCTAssertFalse(String(reflecting: failure).contains(privateContent))
        XCTAssertFalse(failure.localizedDescription.contains(privateContent))
    }
}
