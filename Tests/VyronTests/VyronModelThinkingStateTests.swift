import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronModelThinkingStateTests: XCTestCase {
    func testAdvertisedCapabilityWithoutExactMetadataOffersNoGuessedThinkingControls() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = ollamaProfile()
        test.select(profile, provider: test.provider, capabilities: ["tools", "thinking"])

        XCTAssertEqual(test.model.modelThinkingSupport, .unverified)
        XCTAssertEqual(test.model.modelThinkingSupport(for: profile), .unverified)
        XCTAssertEqual(test.model.modelFeatureReport[.thinking].status, .unverified)
    }

    func testConfirmedNamedLevelsReachActiveAndEditorReportsWithoutInventedOptions() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = ollamaProfile()
        test.select(profile, provider: test.provider, capabilities: ["tools", "thinking"])
        let support = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.low, .high]))
        test.model.recordModelThinkingSupport(support, selection: test.model.modelFeatureSelection(for: profile))

        XCTAssertEqual(test.model.modelThinkingSupport, support)
        XCTAssertEqual(test.model.modelThinkingSupport(for: profile), support)
        XCTAssertTrue(test.model.modelFeatureReport[.thinking].isAvailable)
        XCTAssertEqual(VyronModelThinkingChoice.available(for: test.model.modelThinkingSupport), [
            .automatic, .level(.low), .level(.high),
        ])
        var edited = profile
        edited.settings.temperature = 0.5
        XCTAssertEqual(test.model.modelThinkingSupport(for: edited), support)
    }

    func testBuiltinThinkingOptionsComeFromItsOwnVerifiedSelection() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let name = "qwen3.8:27b"
        test.model.modelSelection.activeConnectionID = nil
        test.model.modelSelection.selectedModel = name
        test.model.modelSelection.models = [LocalModel(name: name, size: 1, capabilities: ["thinking", "tools"])]
        let selection = VyronModelFeatureSelection(
            connection: nil, modelName: name, revision: test.model.modelSelection.connectionRevision
        )
        let support = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.medium, .high]))
        XCTAssertEqual(test.model.modelThinkingSupport, .unverified)

        test.model.recordModelThinkingSupport(support, selection: selection)

        XCTAssertEqual(test.model.modelThinkingSupport, support)
        XCTAssertTrue(test.model.modelFeatureReport[.thinking].isAvailable)
        XCTAssertEqual(VyronModelThinkingChoice.available(for: support), [
            .automatic, .level(.medium), .level(.high),
        ])
    }

    func testThinkingVerificationCannotCrossConnectionModelOrRevision() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = ollamaProfile()
        test.select(profile, provider: test.provider, capabilities: ["tools"])
        let selection = test.model.modelFeatureSelection(for: profile)
        let support = VyronModelThinkingSupport.levels(VyronModelThinkingLevels(levels: [.high]))
        test.model.recordModelThinkingSupport(support, selection: selection)
        var otherEndpoint = profile
        otherEndpoint.endpoint = "http://localhost:22434"
        XCTAssertEqual(test.model.modelThinkingSupport(for: otherEndpoint), .unverified)
        var otherModel = profile
        otherModel.selectedModel = "another-model"
        XCTAssertEqual(test.model.modelThinkingSupport(for: otherModel), .unverified)
        test.model.modelSelection.connectionRevision = UUID()
        test.model.recordModelThinkingSupport(.boolean, selection: selection)

        XCTAssertEqual(test.model.modelThinkingSupport, .unverified)
        XCTAssertEqual(test.model.modelFeatures.thinkingChecks.count, 1)
    }

    func testCompatibleConnectionCannotReuseAnOllamaThinkingCheck() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = test.profile()
        test.select(profile, provider: test.provider, capabilities: ["thinking"])
        test.model.recordModelThinkingSupport(.boolean, selection: test.model.modelFeatureSelection(for: profile))

        XCTAssertEqual(test.model.modelThinkingSupport, .unsupported)
        XCTAssertEqual(test.model.modelThinkingSupport(for: profile), .unsupported)
        XCTAssertFalse(test.model.modelFeatureReport[.thinking].isAvailable)
    }

    private func ollamaProfile() -> ModelConnectionProfile {
        ModelConnectionProfile(
            name: "Thinking fixture",
            kind: .ollama,
            endpoint: "http://localhost:11434",
            selectedModel: "qwen3.8:27b"
        )
    }
}
