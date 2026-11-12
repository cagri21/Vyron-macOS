import VyronCore
import XCTest
@testable import Vyron

final class VyronModelSettingsDraftTests: XCTestCase {
    func testSupportedThinkingKeepsAllConfiguredSettings() throws {
        let settings = configuredSettings()
        let draft = VyronModelSettingsDraft(settings)

        XCTAssertEqual(try draft.settings(thinkingSupport: .boolean), settings)
    }

    func testUnavailableThinkingMustBeReconciledWithoutChangingOtherSettings() throws {
        let settings = configuredSettings()
        var draft = VyronModelSettingsDraft(settings)
        let originalDraft = draft

        XCTAssertThrowsError(try draft.settings(thinkingSupport: .unsupported))
        XCTAssertEqual(draft, originalDraft)
        XCTAssertEqual(try draft.settings(thinkingSupport: .boolean).thinking, true)
        draft.reconcileThinking(with: .unsupported)
        let sanitized = try draft.settings(thinkingSupport: .unsupported)

        XCTAssertNil(sanitized.thinking)
        XCTAssertEqual(sanitized.contextTokens, settings.contextTokens)
        XCTAssertEqual(sanitized.maxOutputTokens, settings.maxOutputTokens)
        XCTAssertEqual(sanitized.temperature, settings.temperature)
        XCTAssertEqual(sanitized.topP, settings.topP)
        XCTAssertEqual(draft.thinking, .automatic)
    }

    func testAutomaticSettingsRemainAutomaticWhenThinkingIsUnavailable() throws {
        let draft = VyronModelSettingsDraft(ModelSettings())

        XCTAssertEqual(try draft.settings(thinkingSupport: .unsupported), ModelSettings())
    }

    func testNamedThinkingSelectionKeepsBudgetsAndClearsBooleanPreference() throws {
        var settings = configuredSettings()
        settings.thinking = nil
        settings.thinkingLevel = .high
        let draft = VyronModelSettingsDraft(settings)
        let support = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.low, .high]))

        XCTAssertEqual(draft.thinking, .level(.high))
        XCTAssertEqual(try draft.settings(thinkingSupport: support), settings)
        XCTAssertNil(try draft.settings(thinkingSupport: support).thinking)
        XCTAssertEqual(try draft.settings(thinkingSupport: support).thinkingLevel, .high)
    }

    func testThinkingChoicesMatchAdvertisedNamedLevelsAndBooleanFlags() {
        let levels = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.high, .low, .high]))
        XCTAssertEqual(VyronModelThinkingChoice.available(for: levels), [.automatic, .level(.low), .level(.high)])
        let mixed = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(
            levels: [.medium], supportsOn: false, supportsOff: true
        ))
        XCTAssertEqual(VyronModelThinkingChoice.available(for: mixed), [.automatic, .disabled, .level(.medium)])
        XCTAssertEqual(VyronModelThinkingChoice.available(for: .levels(VyronModelThinkingLevels(
            levels: [], supportsOn: true
        ))), [.automatic, .enabled])
        XCTAssertEqual(VyronModelThinkingChoice.available(for: .levels(VyronModelThinkingLevels(
            levels: [], supportsOff: true
        ))), [.automatic, .disabled])
        XCTAssertEqual(VyronModelThinkingChoice.available(for: .boolean), [.automatic, .enabled, .disabled])
        for support in [VyronModelThinkingSupport.unverified, .unsupported, .providerDefaultOnly] {
            XCTAssertEqual(VyronModelThinkingChoice.available(for: support), [.automatic])
        }
    }

    func testUnsupportedNamedLevelIsRejectedAndConfirmedModelChangeReconcilesIt() throws {
        var draft = VyronModelSettingsDraft(ModelSettings())
        draft.thinking = .level(.medium)
        let support = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.low, .high]))

        XCTAssertThrowsError(try draft.settings(thinkingSupport: support))
        XCTAssertThrowsError(try draft.settings(thinkingSupport: .boolean))
        draft.reconcileThinking(with: support)
        XCTAssertEqual(draft.thinking, .automatic)
        let settings = try draft.settings(thinkingSupport: support)
        XCTAssertNil(settings.thinking)
        XCTAssertNil(settings.thinkingLevel)
    }

    func testPendingMetadataPreservesSavedSelectionForCapabilityVerification() throws {
        var draft = VyronModelSettingsDraft(configuredSettings())
        draft.reconcileThinking(with: .unverified)

        XCTAssertEqual(draft.thinking, .enabled)
        XCTAssertEqual(try draft.settings(thinkingSupport: .unverified).thinking, true)
        XCTAssertEqual(VyronModelThinkingChoice.available(for: .unverified), [.automatic])
        draft.reconcileThinking(with: .boolean)
        XCTAssertEqual(draft.thinking, .enabled)
    }

    func testSwitchingFromLevelToBooleanClearsThePreviousLevel() throws {
        var settings = ModelSettings()
        settings.thinkingLevel = .high
        var draft = VyronModelSettingsDraft(settings)
        draft.thinking = .disabled

        let saved = try draft.settings(thinkingSupport: .boolean)
        XCTAssertEqual(saved.thinking, false)
        XCTAssertNil(saved.thinkingLevel)
    }

    private func configuredSettings() -> ModelSettings {
        var settings = ModelSettings()
        settings.contextTokens = 16_384
        settings.maxOutputTokens = 4_096
        settings.temperature = 0.6
        settings.topP = 0.9
        settings.thinking = true
        return settings
    }
}
