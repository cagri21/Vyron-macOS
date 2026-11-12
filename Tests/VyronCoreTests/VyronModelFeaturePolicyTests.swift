import Foundation
import XCTest
@testable import VyronCore

final class VyronModelFeaturePolicyTests: XCTestCase {
    func testKnownHostedDeepSeekSelectionsUseVerifiedToolsAndNativeThinkingToggle() {
        let modelIDs = [
            "deepseek-flash", "deepseek-v4-flash", "deepseek-v4-flash-vision-exp", "deepseek-v4-pro",
            "deepseek-chat", "deepseek-reasoner", "DeepSeek-V4.1-Flash-1017", "deepseek-v4-pro-0813"
        ]
        for modelID in modelIDs {
            let profile = connection(endpoint: "https://api.deepseek.com/v1", model: modelID)
            let report = assessment(
                connection: profile,
                name: modelID,
                capabilities: ["tools", "thinking"],
                verification: .verified
            )

            XCTAssertTrue(report[.chat].isAvailable, modelID)
            for feature in [VyronModelFeature.agent, .plan, .mcp] {
                XCTAssertEqual(report[feature].status, .available, modelID)
                XCTAssertNil(report[feature].reason, modelID)
                XCTAssertTrue(report[feature].isEnabled, modelID)
            }
            XCTAssertTrue(report[.thinking].isAvailable, modelID)
            XCTAssertEqual(report[.mac].reason, .builtinConnectionRequired)
            XCTAssertEqual(report[.browser].reason, .builtinConnectionRequired)
        }
    }

    func testDeepSeekControlsUseExactHostAndKnownModelInsteadOfNameSubstring() {
        let localProfile = connection(endpoint: "http://localhost:1234/v1", model: "deepseek-v4-pro")
        let localReport = assessment(
            connection: localProfile,
            name: "deepseek-v4-pro",
            capabilities: ["tools"]
        )
        XCTAssertTrue(localReport[.agent].isAvailable)

        let otherHost = connection(endpoint: "https://api.deepseek.com.example.test/v1", model: "deepseek-flash")
        XCTAssertTrue(assessment(connection: otherHost, name: "deepseek-flash")[.agent].isEnabled)
        XCTAssertEqual(
            assessment(connection: otherHost, name: "deepseek-flash")[.thinking].reason,
            .thinkingControlsUnsupportedByConnection
        )

        let unknownHosted = connection(endpoint: "https://api.deepseek.com/v1", model: "future-deepseek-model")
        let unknownReport = assessment(connection: unknownHosted, name: "future-deepseek-model")
        XCTAssertEqual(unknownReport[.agent].status, .unverified)
        XCTAssertTrue(unknownReport[.agent].isEnabled)
        XCTAssertEqual(unknownReport[.thinking].status, .unverified)

        let knownHosted = connection(endpoint: "https://api.deepseek.com/v1", model: "deepseek-flash")
        let unchecked = assessment(connection: knownHosted, name: "deepseek-flash")
        XCTAssertEqual(unchecked[.agent].status, .unverified, "A provider name must not skip the native tool check")

        let ollamaProfile = connection(
            kind: .ollama,
            endpoint: "http://localhost:11434",
            model: "deepseek-v4-pro"
        )
        XCTAssertTrue(
            assessment(connection: ollamaProfile, name: "deepseek-v4-pro", capabilities: ["tools"])[.agent]
                .isAvailable
        )
    }

    func testOpenAICompatibleMissingToolAdvertisementStillAllowsTheExistingProbe() {
        let profile = connection()
        let metadataExamples: [[String]?] = [nil, [], ["completion"]]
        for capabilities in metadataExamples {
            let report = assessment(connection: profile, capabilities: capabilities)
            XCTAssertEqual(report[.agent].status, .unverified)
            XCTAssertEqual(report[.agent].reason, .nativeToolsUnverified)
            XCTAssertTrue(report[.agent].isEnabled)
            XCTAssertEqual(report[.plan].status, .unverified)
            XCTAssertEqual(report[.mcp].status, .unverified)
        }
    }

    func testAdvertisedToolsAndProbeOutcomesAreSelectionSpecific() {
        let profile = connection()
        XCTAssertTrue(assessment(connection: profile, capabilities: ["tools"])[.agent].isAvailable)

        let verified = assessment(connection: profile, capabilities: ["completion"], verification: .verified)
        XCTAssertTrue(verified[.agent].isAvailable)

        let unsupported = assessment(connection: profile, capabilities: ["tools"], verification: .unsupported)
        XCTAssertFalse(unsupported[.agent].isEnabled)
        XCTAssertEqual(unsupported[.agent].reason, .nativeToolsUnsupported)
        XCTAssertTrue(unsupported[.chat].isAvailable)

        let failed = assessment(connection: profile, capabilities: ["tools"], verification: .failed)
        XCTAssertEqual(failed[.agent].status, .unverified)
        XCTAssertEqual(failed[.agent].reason, .nativeToolVerificationFailed)
        XCTAssertTrue(failed[.agent].isEnabled)

        let anotherSelection = assessment(connection: profile, name: "another-model")
        XCTAssertEqual(anotherSelection[.agent].status, .unverified)
    }

    func testOllamaToolMetadataDistinguishesMissingFromAdvertisedUnsupported() {
        let unknown = assessment()
        XCTAssertEqual(unknown[.agent].status, .unverified)
        XCTAssertTrue(unknown[.agent].isEnabled)
        XCTAssertEqual(assessment(capabilities: [])[.agent].status, .unverified)

        let unsupported = assessment(capabilities: ["completion"])
        XCTAssertEqual(unsupported[.agent].status, .unavailable)
        XCTAssertEqual(unsupported[.agent].reason, .nativeToolsNotAdvertised)

        let supported = assessment(capabilities: ["completion", "tools"])
        XCTAssertTrue(supported[.agent].isAvailable)
        XCTAssertTrue(supported[.plan].isAvailable)
        XCTAssertTrue(supported[.mcp].isAvailable)
    }

    func testCuratedCodingFallbackPreservesInstalledModelBehavior() {
        let report = assessment(name: "qwen3.8:27b")
        XCTAssertTrue(report[.chat].isAvailable)
        XCTAssertTrue(report[.agent].isAvailable)
        XCTAssertTrue(report[.plan].isAvailable)
        XCTAssertTrue(report[.mcp].isAvailable)
        XCTAssertEqual(report[.thinking].status, .unverified)
        XCTAssertTrue(assessment(name: "qwen3.8:27b", capabilities: [])[.agent].isAvailable)
    }

    func testRoutingHelperRemainsChatOnlyEvenWhenToolsWereAdvertisedOrVerified() {
        let report = assessment(
            name: "qwen3:4b",
            capabilities: ["tools", "thinking"],
            verification: .verified
        )
        XCTAssertTrue(report[.chat].isAvailable)
        XCTAssertEqual(report[.thinking].status, .unverified)
        for feature in [VyronModelFeature.agent, .plan, .mcp] {
            XCTAssertFalse(report[feature].isEnabled)
            XCTAssertEqual(report[feature].reason, .helperModelReservedForChat)
        }
    }

    func testThinkingControlsReflectTheImplementedAdapterWithoutDisablingEffortBudgets() {
        let compatible = assessment(connection: connection(), capabilities: ["tools", "thinking"])
        XCTAssertEqual(compatible[.thinking].status, .unavailable)
        XCTAssertEqual(compatible[.thinking].reason, .thinkingControlsUnsupportedByConnection)
        XCTAssertTrue(compatible[.agent].isEnabled)

        let ollama = assessment(capabilities: ["tools", "thinking"])
        XCTAssertEqual(ollama[.thinking].status, .unverified)
        XCTAssertEqual(ollama[.thinking].reason, .thinkingUnverified)

        let nonThinking = assessment(capabilities: ["tools"])
        XCTAssertEqual(nonThinking[.thinking].status, .unavailable)
        XCTAssertTrue(nonThinking[.agent].isEnabled)

        let unknown = assessment()
        XCTAssertEqual(unknown[.thinking].status, .unverified)
        XCTAssertFalse(unknown[.thinking].isAvailable)

        let catalogFallback = assessment(name: "qwen3.8:27b", capabilities: ["tools"])
        XCTAssertEqual(catalogFallback[.thinking].status, .unverified)
        XCTAssertFalse(assessment(name: "qwen3-coder:30b")[.thinking].isAvailable)
    }

    func testMacAndBrowserStayRestrictedToTheBuiltInConnection() {
        let builtin = assessment()
        XCTAssertTrue(builtin[.mac].isAvailable)
        XCTAssertTrue(builtin[.browser].isAvailable)

        let configuredLocal = assessment(
            connection: connection(kind: .ollama, endpoint: "http://localhost:11434")
        )
        for feature in [VyronModelFeature.mac, .browser] {
            XCTAssertFalse(configuredLocal[feature].isEnabled)
            XCTAssertEqual(configuredLocal[feature].reason, .builtinConnectionRequired)
        }
    }

    func testUnknownThinkingLevelsPreserveDefaultsDespiteTheCapabilityAndCatalogFallback() {
        let report = VyronModelFeaturePolicy.assess(
            VyronModelFeatureContext(
                model: LocalModel(name: "qwen3.8:27b", size: 0, capabilities: ["tools", "thinking"]),
                thinkingSupport: .providerDefaultOnly
            )
        )
        XCTAssertEqual(report[.thinking].status, .unavailable)
        XCTAssertEqual(report[.thinking].reason, .thinkingLevelsUnsupported)
        XCTAssertTrue(report[.chat].isAvailable)
        XCTAssertTrue(report[.agent].isAvailable)
    }

    func testThinkingMetadataCanConfirmBooleanSupportOrRejectACatalogAssumption() {
        let boolean = VyronModelFeaturePolicy.assess(
            VyronModelFeatureContext(
                model: LocalModel(name: "custom-model", size: 0),
                thinkingSupport: .boolean
            )
        )
        XCTAssertTrue(boolean[.thinking].isAvailable)

        let unsupported = VyronModelFeaturePolicy.assess(
            VyronModelFeatureContext(
                model: LocalModel(name: "qwen3.8:27b", size: 0),
                thinkingSupport: .unsupported
            )
        )
        XCTAssertEqual(unsupported[.thinking].status, .unavailable)
        XCTAssertEqual(unsupported[.thinking].reason, .thinkingNotAdvertised)
        XCTAssertTrue(unsupported[.agent].isAvailable)
    }

    func testAdvertisedNamedLevelsEnableControlsOnlyAfterTheirShapeIsKnown() {
        let model = LocalModel(name: "qwen3.8:27b", size: 0, capabilities: ["tools", "thinking"])
        let unknown = VyronModelFeaturePolicy.assess(VyronModelFeatureContext(model: model))
        XCTAssertEqual(unknown[.thinking].status, .unverified)

        let known = VyronModelFeaturePolicy.assess(VyronModelFeatureContext(
            model: model,
            thinkingSupport: .levels(VyronModelThinkingLevels(levels: [.low, .high]))
        ))
        XCTAssertTrue(known[.thinking].isAvailable)
        XCTAssertTrue(known[.agent].isAvailable)
    }

    func testAnEmptyControlPayloadDoesNotEnableUnsupportedControls() {
        let controls = VyronModelThinkingLevels(levels: [])
        XCTAssertFalse(controls.hasControls)
        let report = VyronModelFeaturePolicy.assess(VyronModelFeatureContext(
            model: LocalModel(name: "custom-model", size: 0),
            thinkingSupport: .levels(controls)
        ))
        XCTAssertEqual(report[.thinking].status, .unavailable)
        XCTAssertEqual(report[.thinking].reason, .thinkingLevelsUnsupported)
    }

    func testThinkingVerificationCannotEnableAnUnsupportedConnectionAdapter() {
        let report = VyronModelFeaturePolicy.assess(
            VyronModelFeatureContext(
                connection: connection(),
                model: LocalModel(name: "custom-model", size: 0, capabilities: ["thinking"]),
                thinkingSupport: .boolean
            )
        )
        XCTAssertEqual(report[.thinking].status, .unavailable)
        XCTAssertEqual(report[.thinking].reason, .thinkingControlsUnsupportedByConnection)
    }

    func testReportsHaveStableFeatureOrderAndUnknownSelectionIsNotReportedAsUnsupported() {
        let report = assessment(name: "")
        XCTAssertEqual(report.features.map(\.feature), VyronModelFeature.allCases)
        XCTAssertEqual(report[.chat].status, .unverified)
        XCTAssertEqual(report[.agent].reason, .modelNotSelected)
        XCTAssertTrue(report[.agent].isEnabled)
        XCTAssertFalse(report.unavailableFeatures.contains { $0.feature == .agent })
    }

    private func assessment(
        connection: ModelConnectionProfile? = nil,
        name: String = "custom-model",
        capabilities: [String]? = nil,
        verification: VyronNativeToolVerification = .unverified
    ) -> VyronModelFeatureReport {
        VyronModelFeaturePolicy.assess(
            VyronModelFeatureContext(
                connection: connection,
                model: LocalModel(name: name, size: 0, capabilities: capabilities),
                toolVerification: verification
            )
        )
    }

    private func connection(
        kind: ModelProviderKind = .openAICompatible,
        endpoint: String = "https://models.example.test/v1",
        model: String = "custom-model"
    ) -> ModelConnectionProfile {
        ModelConnectionProfile(name: "Test connection", kind: kind, endpoint: endpoint, selectedModel: model)
    }
}
