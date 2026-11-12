import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronDeepSeekConnectionThinkingTests: XCTestCase {
    func testOfficialPresetExposesThinkingToggleInActiveAndEditorModels() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = VyronDeepSeekConnectionPreset.makeProfile()
        test.select(profile, provider: test.provider, capabilities: ["tools"])

        XCTAssertEqual(test.model.modelThinkingSupport, .boolean)
        XCTAssertEqual(test.model.modelThinkingSupport(for: profile), .boolean)
        XCTAssertEqual(test.model.modelFeatureReport[.thinking].status, .available)
        XCTAssertEqual(VyronModelThinkingChoice.available(for: test.model.modelThinkingSupport), [
            .automatic, .enabled, .disabled,
        ])

        for enabled in [true, false] {
            var draft = VyronModelSettingsDraft(profile.settings)
            draft.thinking = enabled ? .enabled : .disabled
            var edited = profile
            edited.settings = try draft.settings(thinkingSupport: test.model.modelThinkingSupport(for: profile))

            XCTAssertEqual(try edited.validated().settings.thinking, enabled)
            XCTAssertNil(edited.settings.thinkingLevel)
        }
    }

    func testUnknownOfficialModelDoesNotInheritKnownModelThinkingToggle() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        var profile = VyronDeepSeekConnectionPreset.makeProfile()
        test.select(profile, provider: test.provider, capabilities: ["tools", "thinking"])
        XCTAssertEqual(test.model.modelThinkingSupport, .boolean)

        profile.selectedModel = "unverified-future-model"
        test.select(profile, provider: test.provider, capabilities: ["tools", "thinking"])

        XCTAssertEqual(test.model.modelThinkingSupport, .unverified)
        XCTAssertEqual(test.model.modelThinkingSupport(for: profile), .unverified)
        XCTAssertEqual(VyronModelThinkingChoice.available(for: test.model.modelThinkingSupport), [.automatic])
    }

    func testDeepSeekModelOnThirdPartyHostDoesNotReceiveOfficialThinkingControls() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }

        for endpoint in ["https://models.example.test/v1", "https://api.deepseek.com.example.test/v1"] {
            var profile = VyronDeepSeekConnectionPreset.makeProfile()
            profile.endpoint = endpoint
            test.select(profile, provider: test.provider, capabilities: ["tools", "thinking"])
            test.model.recordModelThinkingSupport(.boolean, selection: test.model.modelFeatureSelection(for: profile))

            XCTAssertEqual(test.model.modelThinkingSupport, .unsupported)
            XCTAssertEqual(test.model.modelThinkingSupport(for: profile), .unsupported)
            XCTAssertEqual(VyronModelThinkingChoice.available(for: test.model.modelThinkingSupport), [.automatic])
            var edited = profile
            edited.settings.thinking = true
            XCTAssertThrowsError(try edited.validated())
        }
    }
}
