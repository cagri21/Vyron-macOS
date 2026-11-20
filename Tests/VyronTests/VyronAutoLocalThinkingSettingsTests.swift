import XCTest
@testable import Vyron
import VyronModelDomain

final class VyronAutoLocalThinkingSettingsTests: XCTestCase {
    func testVerifiedBooleanControlTracksSelectedEffortWithoutChangingSavedSettings() {
        let saved = ModelSettings()
        XCTAssertEqual(
            VyronAutoLocalThinkingSettings.applying(to: saved, support: .boolean, effort: .quick).thinking, false
        )
        XCTAssertEqual(
            VyronAutoLocalThinkingSettings.applying(to: saved, support: .boolean, effort: .deep).thinking, true
        )
        XCTAssertNil(saved.thinking)
    }

    func testOnlyAdvertisedLevelsAreApplied() {
        let support = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.low, .high]))
        XCTAssertEqual(
            VyronAutoLocalThinkingSettings.applying(to: ModelSettings(), support: support, effort: .deep).thinkingLevel,
            .high
        )
        let balanced = VyronAutoLocalThinkingSettings.applying(
            to: ModelSettings(), support: support, effort: .balanced
        )
        XCTAssertNil(balanced.thinkingLevel)
        for support in [VyronModelThinkingSupport.unverified, .unsupported, .providerDefaultOnly] {
            XCTAssertEqual(
                VyronAutoLocalThinkingSettings.applying(to: ModelSettings(), support: support, effort: .deep),
                ModelSettings()
            )
        }
    }

    func testExplicitSavedThinkingPreferenceWins() {
        var saved = ModelSettings(thinking: false)
        XCTAssertEqual(VyronAutoLocalThinkingSettings.applying(to: saved, support: .boolean, effort: .deep), saved)
        saved.thinking = nil
        saved.thinkingLevel = .low
        XCTAssertEqual(
            VyronAutoLocalThinkingSettings.applying(
                to: saved, support: .levels(VyronModelThinkingLevels(levels: [.low, .high])), effort: .deep
            ),
            saved
        )
    }
}
