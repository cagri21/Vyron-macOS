import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronModelRankingPresentationTests: XCTestCase {
    func testRankedModelsHelpersAndUnratedModelsKeepDistinctStableSections() {
        let newest = LocalModel(name: "qwen3.8:27b", size: 18_000_000_000, capabilities: ["tools"])
        let coder = LocalModel(name: "qwen3-coder:30b", size: 19_000_000_000, capabilities: ["tools"])
        let helper = LocalModel(name: "qwen3:4b", size: 2_500_000_000, capabilities: ["tools"])
        let heavy = LocalModel(name: "qwen3-coder-next:q4_K_M", size: 52_000_000_000, capabilities: ["tools"])
        let unrated = LocalModel(name: "plain:latest", size: 1, capabilities: ["completion"])
        let models = [heavy, helper, coder, unrated, newest]
        let ranking = VyronModelRankingPresentation(
            models: models,
            rankings: AgentModelRouter.rankedCodingModels(from: models, selectedModel: coder.name, effort: .balanced),
            isBuiltinConnection: true
        )

        XCTAssertEqual(ranking.scoredModels.map { $0.model.name }, [newest.name, coder.name])
        XCTAssertEqual(ranking.chatHelpers.map(\.name), [helper.name])
        XCTAssertEqual(ranking.otherModels.map(\.name), [heavy.name, unrated.name])
        XCTAssertEqual(Set(ranking.allModels.map(\.name)), Set(models.map(\.name)))
        XCTAssertNil(ranking.score(for: helper.name))
        XCTAssertNil(ranking.score(for: heavy.name))
        XCTAssertNil(ranking.score(for: unrated.name))
        XCTAssertEqual(models.map(\.name), [heavy.name, helper.name, coder.name, unrated.name, newest.name])
    }

    func testCustomConnectionsStayUnratedEvenForKnownLocalModelNames() {
        let models = [LocalModel(name: "qwen3:4b", size: 0), LocalModel(name: "qwen3.8:27b", size: 0)]
        let ranking = VyronModelRankingPresentation(
            models: models,
            rankings: [VyronScoredModel(model: models[1], score: 500)],
            isBuiltinConnection: false
        )

        XCTAssertTrue(ranking.scoredModels.isEmpty)
        XCTAssertTrue(ranking.chatHelpers.isEmpty)
        XCTAssertEqual(ranking.otherModels.map(\.name), models.map(\.name))
        XCTAssertNil(ranking.score(for: models[1].name))
    }

    func testScoreFormattingShowsRawPointsWithTheRequestedLocale() {
        XCTAssertEqual(VyronModelScorePresentation.points(512.34, locale: Locale(identifier: "en_US")), "512.3")
        XCTAssertEqual(VyronModelScorePresentation.points(512.34, locale: Locale(identifier: "tr_TR")), "512,3")
        XCTAssertEqual(VyronModelScorePresentation.points(-2.34, locale: Locale(identifier: "en_US")), "-2.3")
    }

    func testReadingRankingsPreservesAutoAndExactManualSelection() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let newest = LocalModel(name: "library/qwen3.8:27b", size: 18_000_000_000, capabilities: ["tools"])
        let coder = LocalModel(name: "qwen3-coder:30b", size: 19_000_000_000, capabilities: ["tools"])
        let helper = LocalModel(name: "qwen3:4b", size: 2_500_000_000, capabilities: ["tools"])
        test.model.modelSelection.activeConnectionID = nil
        test.model.modelSelection.models = [helper, coder, newest]
        test.model.modelSelection.selectedModel = coder.name
        test.model.modelSelection.automaticModelSelection = true
        let originalNames = test.model.modelSelection.models.map(\.name)

        XCTAssertEqual(test.model.modelRanking.scoredModels.first?.model.name, newest.name)
        XCTAssertTrue(test.model.modelSelection.automaticModelSelection)
        XCTAssertEqual(test.model.modelSelection.selectedModel, coder.name)
        XCTAssertEqual(test.model.modelSelection.models.map(\.name), originalNames)

        test.model.useLocalModel(newest.name)
        XCTAssertFalse(test.model.modelSelection.automaticModelSelection)
        XCTAssertEqual(test.model.modelSelection.selectedModel, newest.name)
        XCTAssertTrue(test.model.modelSelection.isSelectedModel(newest.name))
        XCTAssertFalse(test.model.modelSelection.isSelectedModel(coder.name))
        XCTAssertEqual(test.model.modelSelection.models.map(\.name), originalNames)
        test.model.composer.mode = .agent
        test.model.useLocalModel(helper.name, forChat: true)
        XCTAssertEqual(test.model.composer.mode, .chat)
        XCTAssertEqual(test.model.modelSelection.selectedModel, helper.name)
    }

    func testUnratedCustomChoiceKeepsItsExactIdentifierAndConnection() throws {
        let test = try VyronFeatureTestHarness()
        defer { test.cleanUp() }
        let profile = test.profile(modelName: "vendor/original:q4")
        test.select(profile, provider: test.provider, capabilities: ["tools"])
        let other = LocalModel(name: "vendor/Custom-Q4:exact", size: 0)
        test.model.modelSelection.models.append(other)
        let revision = test.model.modelSelection.connectionRevision

        XCTAssertTrue(test.model.modelRanking.scoredModels.isEmpty)
        XCTAssertEqual(test.model.modelRanking.otherModels.map(\.name), [profile.selectedModel, other.name])
        test.model.useLocalModel(other.name)

        XCTAssertEqual(test.model.modelSelection.selectedModel, other.name)
        XCTAssertEqual(test.model.modelSelection.activeConnectionID, profile.id)
        XCTAssertEqual(test.model.modelSelection.connectionProfiles.first?.selectedModel, other.name)
        XCTAssertEqual(test.model.modelSelection.connectionRevision, revision)
        XCTAssertTrue(test.model.modelSelection.isSelectedModel(other.name))
        XCTAssertNil(test.model.modelRanking.score(for: other.name))
    }
}
