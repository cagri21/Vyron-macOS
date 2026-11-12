import Foundation
import XCTest
@testable import VyronCore

final class VyronModelRankingTests: XCTestCase {
    func testRankingExposesTheExistingRawPreferencePoints() throws {
        let imported = model("my-coder:latest", size: 12_000_000_000)
        let balanced = try XCTUnwrap(AgentModelRouter.rankedCodingModels(
            from: [imported], selectedModel: imported.name, effort: .balanced
        ).first)
        XCTAssertEqual(balanced.model, imported)
        XCTAssertEqual(balanced.id, imported.id)
        XCTAssertEqual(balanced.score, 6.5, accuracy: 0.000_001)

        let deep = try XCTUnwrap(AgentModelRouter.rankedCodingModels(
            from: [imported], selectedModel: imported.name, effort: .deep
        ).first)
        XCTAssertEqual(deep.score, 6.5 + log1p(12), accuracy: 0.000_001)
    }

    func testCatalogOrderAndAutomaticWinnerRemainIdenticalAcrossEffortsAndInputOrder() throws {
        let installed = [
            model("qwen3-coder:30b", size: 19_000_000_000),
            model("devstral-small-2:24b", size: 15_000_000_000),
            model("qwen3.6:35b", size: 23_000_000_000),
            model("qwen3.8:27b", size: 18_000_000_000)
        ]
        let expected = ["qwen3.8:27b", "qwen3.6:35b", "devstral-small-2:24b", "qwen3-coder:30b"]
        for input in [installed, Array(installed.reversed())] {
            for effort in AgentEffort.allCases {
                let ranking = AgentModelRouter.rankedCodingModels(
                    from: input, selectedModel: "qwen3-coder:30b", effort: effort
                )
                XCTAssertEqual(ranking.map(\.id), expected)
                XCTAssertEqual(ranking.first?.model, try AgentModelRouter.selectCodingModel(
                    from: input, selectedModel: "qwen3-coder:30b", effort: effort
                ))
                XCTAssertTrue(zip(ranking, ranking.dropFirst()).allSatisfy { pair in pair.0.score >= pair.1.score })
            }
        }
    }

    func testCodingQuickAndAutomaticUseBalancedPointsWithoutChangingQuickChatRouting() {
        let imported = model("imported:latest", size: 12_000_000_000)
        let helper = model("qwen3:4b", size: 2_500_000_000)
        let input = [helper, imported]
        let balanced = AgentModelRouter.rankedCodingModels(
            from: input, selectedModel: imported.name, effort: .balanced
        )
        for effort in [AgentEffort.quick, .automatic] {
            XCTAssertEqual(AgentModelRouter.rankedCodingModels(
                from: input, selectedModel: imported.name, effort: effort
            ), balanced)
        }
        XCTAssertEqual(AgentModelRouter.selectModel(from: input, effort: .quick), helper)
        XCTAssertEqual(balanced.map(\.model), [imported])
    }

    func testEqualPointsUseDeterministicNamesAndTheExistingExactPreferenceBonus() {
        let alpha = model("alpha:latest", size: 12_000_000_000)
        let beta = model("beta:latest", size: 12_000_000_000)
        for input in [[alpha, beta], [beta, alpha]] {
            let alphabetical = AgentModelRouter.rankedCodingModels(
                from: input, selectedModel: "missing:latest", effort: .balanced
            )
            XCTAssertEqual(alphabetical.map(\.id), [alpha.id, beta.id])
            XCTAssertEqual(alphabetical.map(\.score), [3, 3])
            let preferred = AgentModelRouter.rankedCodingModels(
                from: input, selectedModel: beta.name, effort: .balanced
            )
            XCTAssertEqual(preferred.map(\.id), [beta.id, alpha.id])
            XCTAssertEqual(preferred.map(\.score), [3.5, 3])
        }
    }

    func testOnlyEligibleAutomaticCodingCandidatesReceiveScores() {
        let verified = model("imported:latest", size: 1_000_000_000)
        let input = [
            verified,
            model("unknown:latest", size: 1_000_000_000, capabilities: nil),
            model("no-tools:latest", size: 1_000_000_000, capabilities: ["completion"]),
            model("qwen3:4b", size: 2_500_000_000),
            model("qwen3-coder-next:q4_K_M", size: 52_000_000_000),
            model("oversized:latest", size: 40_000_000_000),
            model("bge-code:latest", size: 1_000_000_000),
            model("remote:cloud", size: 1_000_000_000)
        ]
        XCTAssertEqual(AgentModelRouter.rankedCodingModels(
            from: input, selectedModel: verified.name, effort: .deep
        ).map(\.model), [verified])
    }

    func testScoresAreFiniteForMissingAndExtremeSizeMetadata() {
        let input = [
            model("zero:latest", size: 0),
            model("negative:latest", size: Int64.min),
            model("enormous:latest", size: Int64.max)
        ]
        for effort in AgentEffort.allCases {
            let ranking = AgentModelRouter.rankedCodingModels(
                from: input, selectedModel: "zero:latest", effort: effort
            )
            XCTAssertEqual(Set(ranking.map(\.id)), ["zero:latest", "negative:latest"])
            XCTAssertTrue(ranking.allSatisfy { $0.score.isFinite })
        }
    }

    func testInstalledAliasesAndManualOnlySelectionKeepTheirExistingContracts() throws {
        let aliased = model("library/qwen3.8:latest", size: 18_000_000_000)
        let heavy = model("qwen3-coder-next:q4_K_M", size: 52_000_000_000)
        let helper = model("qwen3:4b", size: 2_500_000_000)
        let input = [heavy, helper, aliased]
        XCTAssertEqual(AgentModelRouter.rankedCodingModels(
            from: input, selectedModel: heavy.name, effort: .balanced
        ).map(\.id), [aliased.id])
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(
            from: input, selectedModel: "qwen3.8", automaticModelSelection: false
        ), aliased)
        XCTAssertEqual(try AgentModelRouter.selectCodingModel(
            from: input, selectedModel: heavy.name, automaticModelSelection: false
        ), heavy)
        XCTAssertThrowsError(try AgentModelRouter.selectCodingModel(
            from: input, selectedModel: helper.name, automaticModelSelection: false
        ))
        XCTAssertThrowsError(try AgentModelRouter.selectCodingModel(
            from: input, selectedModel: "missing:latest", automaticModelSelection: false
        ))
        XCTAssertThrowsError(try AgentModelRouter.selectCodingModel(from: input, selectedModel: "../invalid"))
        XCTAssertTrue(AgentModelRouter.rankedCodingModels(
            from: [], selectedModel: aliased.name, effort: .balanced
        ).isEmpty)
    }

    private func model(
        _ name: String,
        size: Int64,
        capabilities: [String]? = ["completion", "tools"]
    ) -> LocalModel {
        LocalModel(name: name, size: size, capabilities: capabilities)
    }
}
