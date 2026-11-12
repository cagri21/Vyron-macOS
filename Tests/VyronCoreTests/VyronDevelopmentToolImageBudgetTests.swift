import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronDevelopmentToolImageBudgetTests: XCTestCase {
    func testLongOCREvidenceHasAnExplicitBoundedTruncationNote() throws {
        let observation = VyronDevelopmentImageObservation(
            tool: "capture", textEvidence: String(repeating: "x", count: 20_000)
        )
        let text = try XCTUnwrap(observation.textEvidence)
        XCTAssertLessThanOrEqual(text.utf8.count, VyronDevelopmentRunLimits.toolOutputBytes)
        XCTAssertTrue(text.hasSuffix("[Local OCR evidence truncated to fit this observation's context budget.]"))
    }

    func testNativeBudgetDropsAnOlderCaptureAndPreservesUserGuidanceAndLatestCapture() throws {
        let base = [DevelopmentMessage(role: "user", content: "Original task")]
        let guidance = DevelopmentMessage(role: "user", content: "Keep this exact user instruction.")
        let old = capture(tool: "older", textBytes: 2_000)
        let latest = capture(tool: "newest", textBytes: 2_000)
        let result = try boundedDevelopmentMessages(base: base, exchanges: [
            DevelopmentExchange(messages: [guidance]), DevelopmentExchange(messages: [old]),
            DevelopmentExchange(messages: [latest])
        ], maximumBytes: 4_000)

        XCTAssertTrue(result.contains(guidance))
        XCTAssertEqual(result.filter { $0.imageObservation != nil }.map { $0.imageObservation?.tool }, ["newest"])
    }

    func testProviderBudgetDropsOnlyOlderCaptureBeforeRejectingCurrentEvidence() throws {
        let guidance = DevelopmentMessage(role: "user", content: "Keep this exact user instruction.")
        let result = try VyronDevelopmentRequestBudget.messages([
            guidance, capture(tool: "older", textBytes: 1_200), capture(tool: "newest", textBytes: 1_200)
        ], tools: [], budget: .init(contextTokens: 5_000))

        XCTAssertTrue(result.contains(guidance))
        XCTAssertEqual(result.filter { $0.imageObservation != nil }.map { $0.imageObservation?.tool }, ["newest"])
    }

    private func capture(tool: String, textBytes: Int) -> DevelopmentMessage {
        DevelopmentMessage(
            observation: VyronDevelopmentImageObservation(
                tool: tool, textEvidence: String(repeating: "x", count: textBytes)
            ),
            images: []
        )
    }
}
