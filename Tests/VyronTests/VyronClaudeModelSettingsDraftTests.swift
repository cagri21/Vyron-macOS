import XCTest
@testable import Vyron
@testable import VyronCore

final class VyronClaudeModelSettingsDraftTests: XCTestCase {
    func testClaudeDraftSupportsManualBudgetsAndBlankAutomaticValues() throws {
        var profile = VyronClaudeConnectionPreset.makeProfile()
        var draft = VyronModelSettingsDraft(profile.settings)
        draft.budget.contextTokens = " 200000 "
        draft.budget.maxOutputTokens = "64000"
        draft.sampling.temperature = "0.5"
        profile.settings = try draft.settings(thinkingSupport: .unsupported, includesSampling: false)

        let saved = try profile.validated()
        XCTAssertEqual(saved.settings.contextTokens, 200_000)
        XCTAssertEqual(saved.settings.maxOutputTokens, 64_000)
        XCTAssertNil(saved.settings.temperature)

        draft = VyronModelSettingsDraft(saved.settings)
        XCTAssertEqual(draft.budget.contextTokens, "200000")
        XCTAssertEqual(draft.budget.maxOutputTokens, "64000")
        draft.budget.contextTokens = ""
        draft.budget.maxOutputTokens = ""
        profile.settings = try draft.settings(thinkingSupport: .unsupported, includesSampling: false)
        XCTAssertEqual(try profile.validated().settings, ModelSettings())
    }
}
