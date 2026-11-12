import XCTest
@testable import VyronCore

final class ModelCatalogTests: XCTestCase {
    private func model(_ tag: String, size: Int64, capabilities: [String]? = ["completion", "tools"]) -> LocalModel {
        LocalModel(name: tag, size: size, capabilities: capabilities)
    }

    func testCatalogSeparatesCodingChoicesHelperAndManualOnlyHeavyModel() throws {
        XCTAssertEqual(Set(ModelCatalog.all.map(\.tag)).count, 6)
        let recommended = try XCTUnwrap(ModelCatalog.descriptor(for: ModelCatalog.recommendedCodingTag))
        XCTAssertEqual(recommended.tag, "qwen3.8:27b")
        XCTAssertEqual(recommended.role, .coding)
        XCTAssertTrue(recommended.supportsTools)
        XCTAssertTrue(recommended.supportsThinking)
        XCTAssertEqual(recommended.recommendedContextTokens, 32_768)
        XCTAssertEqual(ModelCatalog.descriptor(for: "qwen3:4b")?.role, .helper)
        XCTAssertEqual(ModelCatalog.descriptor(for: "qwen3-coder-next:q4_K_M")?.isAutomaticCodingCandidate, false)
        XCTAssertEqual(ModelCatalog.descriptor(for: "qwen3-coder-next:q4_K_M")?.downloadSizeGB, 52)
    }

    func testAutomaticCodingUsesCatalogPriorityRatherThanCoderSubstringOrPreferredTag() throws {
        let installed = [
            model("qwen3-coder:30b", size: 19_000_000_000),
            model("devstral-small-2:24b", size: 15_000_000_000),
            model("qwen3.6:35b", size: 23_000_000_000),
            model("qwen3.8:27b", size: 18_000_000_000)
        ]
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: "qwen3-coder:30b").name, "qwen3.8:27b")
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: Array(installed.dropLast()), selectedModel: "qwen3-coder:30b").name, "qwen3.6:35b")
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: Array(installed.prefix(2)), selectedModel: "qwen3-coder:30b").name, "devstral-small-2:24b")
    }

    func testExplicitCodingSelectionIsHonoredWithoutSilentFallback() throws {
        let installed = [model("qwen3-coder:30b", size: 19_000_000_000), model("qwen3.8:27b", size: 18_000_000_000)]
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: "qwen3-coder:30b", automaticModelSelection: false).name, "qwen3-coder:30b")
        XCTAssertThrowsError(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: "devstral-small-2:24b", automaticModelSelection: false)) { error in
            XCTAssertEqual(error as? LocalAIError, .modelNotInstalled("devstral-small-2:24b"))
        }
    }

    func testExplicitHelperOrModelWithoutToolsIsRejectedInsteadOfRerouted() throws {
        let installed = [model("qwen3:4b", size: 2_500_000_000), model("qwen3.8:27b", size: 18_000_000_000, capabilities: ["completion"]), model("qwen3-coder:30b", size: 19_000_000_000)]
        for tag in ["qwen3:4b", "qwen3.8:27b"] {
            XCTAssertThrowsError(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: tag, automaticModelSelection: false)) { error in
                guard case .unsupportedModel = error as? DevelopmentAgentError else { return XCTFail("Expected an explicit compatibility error") }
            }
        }
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: "qwen3.8:27b").name, "qwen3-coder:30b")
    }

    func testHeavyModelNeverWinsAnyAutomaticPathButManualSelectionWorks() throws {
        let heavy = model("qwen3-coder-next:q4_K_M", size: 52_000_000_000)
        let coder = model("qwen3-coder:30b", size: 19_000_000_000)
        let newer = model("qwen3.8:27b", size: 18_000_000_000)
        let helper = model("qwen3:4b", size: 2_500_000_000)
        let installed = [heavy, coder, newer, helper]
        XCTAssertEqual(AgentModelRouter.selectModel(from: installed, preferredModel: heavy.name, effort: .deep)?.name, newer.name)
        XCTAssertEqual(AgentModelRouter.selectModel(from: installed, preferredModel: heavy.name, effort: .quick)?.name, helper.name)
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: heavy.name).name, newer.name)
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: heavy.name, automaticModelSelection: false).name, heavy.name)
        XCTAssertNil(AgentModelRouter.selectModel(from: [heavy], effort: .deep))
        XCTAssertThrowsError(try AgentModelRouter.selectCodingModel(from: [heavy, helper], selectedModel: heavy.name))
    }

    func testMissingCapabilitiesUseOnlyVerifiedCatalogMetadata() {
        XCTAssertNil(ModelCatalog.codingIncompatibilityReason(for: model("qwen3.8:27b", size: 18_000_000_000, capabilities: nil)))
        XCTAssertNotNil(ModelCatalog.codingIncompatibilityReason(for: model("unknown-coder:latest", size: 10_000_000_000, capabilities: nil)))
        XCTAssertNotNil(ModelCatalog.codingIncompatibilityReason(for: model("tiny-general:latest", size: 2_500_000_000, capabilities: nil)))
    }

    func testSmallImportedModelUsesVerifiedToolsInsteadOfNameOrWeightSize() throws {
        let small = model("my-import:latest", size: 1_000_000_000, capabilities: ["completion", "tools"])
        XCTAssertNil(ModelCatalog.codingIncompatibilityReason(for: small))
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: [small], selectedModel: small.name, automaticModelSelection: false).name, small.name)
        let unsupported = model("my-import:latest", size: 1_000_000_000, capabilities: ["completion"])
        XCTAssertNotNil(ModelCatalog.codingIncompatibilityReason(for: unsupported))
        XCTAssertThrowsError(try AgentModelRouter.selectCodingModel(from: [unsupported], selectedModel: unsupported.name, automaticModelSelection: false))
    }

    func testDefaultAliasesAffectMetadataWithoutInventingInstalledTags() throws {
        XCTAssertEqual(ModelCatalog.descriptor(for: "library/qwen3.8:latest")?.tag, "qwen3.8:27b")
        XCTAssertEqual(ModelCatalog.descriptor(for: "qwen3.6")?.tag, "qwen3.6:35b")
        XCTAssertEqual(ModelCatalog.descriptor(for: "devstral-small-2:latest")?.tag, "devstral-small-2:24b")
        XCTAssertEqual(ModelCatalog.descriptor(for: "qwen3-coder-next:latest")?.isAutomaticCodingCandidate, false)
        let installed = [model("qwen3.8:latest", size: 18_000_000_000), model("qwen3-coder:30b", size: 19_000_000_000)]
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: "qwen3-coder:30b").name, "qwen3.8:latest")
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: "qwen3.8", automaticModelSelection: false).name, "qwen3.8:latest")
        XCTAssertThrowsError(try AgentModelRouter.selectCodingModel(from: installed, selectedModel: "qwen3.8:27b", automaticModelSelection: false))
    }
}
