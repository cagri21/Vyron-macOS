import XCTest
@testable import VyronCore

final class VyronHostedConnectionPresetTests: XCTestCase {
    func testGeminiPresetCreatesValidatedIndependentDrafts() throws {
        let first = VyronGeminiConnectionPreset.makeProfile()
        let second = VyronGeminiConnectionPreset.makeProfile()

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.name, "Gemini")
        XCTAssertEqual(first.kind, .openAICompatible)
        XCTAssertEqual(first.endpoint, "https://generativelanguage.googleapis.com/v1beta/openai")
        XCTAssertEqual(first.selectedModel, "gemini-3.8-flash")
        XCTAssertEqual(first.settings, ModelSettings())
        XCTAssertTrue(VyronGeminiConnectionPreset.matches(first))
        XCTAssertEqual(try first.validated(), first)
    }

    func testMetaPresetCreatesValidatedIndependentDrafts() throws {
        let first = VyronMetaConnectionPreset.makeProfile()
        let second = VyronMetaConnectionPreset.makeProfile()

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.name, "Meta")
        XCTAssertEqual(first.kind, .openAICompatible)
        XCTAssertEqual(first.endpoint, "https://api.meta.ai/v1")
        XCTAssertEqual(first.selectedModel, "muse-spark-1.3")
        XCTAssertEqual(first.settings, ModelSettings())
        XCTAssertTrue(VyronMetaConnectionPreset.matches(first))
        XCTAssertEqual(try first.validated(), first)
    }
}
