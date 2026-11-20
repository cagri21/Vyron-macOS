import Foundation
import XCTest
@testable import Vyron
import VyronCore
import VyronModelDomain

/// Offline scripted inference verifies native tool transport, not the quality of a real local model's analysis.
@MainActor
final class VyronLargeCodebaseAnalysisTests: XCTestCase {
    func testOfflinePlanAuditsSeededHotspotsInLargeCodebaseWithoutChangingSources() async throws {
        let fixture = try VyronLargeCodebaseAnalysisFixture()
        defer { fixture.cleanUp() }
        await fixture.prepare()
        let prompt = """
        REQUIREMENT_BEGIN: Analyze the whole codebase, observe the architecture, and find improvements.
        REQUIREMENT_MIDDLE: Read concrete source evidence before making recommendations. Remain read-only.
        REQUIREMENT_END: Explain the actual reviewed scope and do not claim that bounded tools read every file.
        """
        fixture.test.model.composer.draft = prompt
        XCTAssertTrue(fixture.test.model.canSend)
        fixture.test.model.send()
        try await fixture.test.waitUntil { !fixture.test.model.foregroundRun.isGenerating }

        try await assertCompletedAudit(fixture, prompt: prompt)
        XCTAssertNil(fixture.test.model.messages.first { $0.conversationRole == .user }?.developmentTaskFilename)
    }

    func testNearLimitMultilingualPlanPromptPreservesEveryRequirementDuringAnalysis() async throws {
        try await exerciseNearLimitPrompt(mode: .plan)
    }

    func testNearLimitMultilingualWorkPromptPreservesEveryRequirementDuringAnalysis() async throws {
        try await exerciseNearLimitPrompt(mode: .agent)
    }

    func testWholeCodebaseSearchCanDiscoverEvidenceBeyondTheFirstInventoryWindow() async throws {
        let fixture = try VyronLargeCodebaseAnalysisFixture()
        defer { fixture.cleanUp() }
        await fixture.prepare()
        let path = try await fixture.plantEvidenceOutsideInitialSearchWindow()

        try await assertSearchFindsEvidence(fixture, path: path, query: "DISCOVERY_BEYOND_INITIAL_WINDOW")
    }

    func testWholeCodebaseSearchCanDiscoverEvidenceAfterFortyKilobytesInOneSource() async throws {
        let fixture = try VyronLargeCodebaseAnalysisFixture(sourceCount: 8)
        defer { fixture.cleanUp() }
        await fixture.prepare()
        let path = try await fixture.plantEvidenceAfterSearchByteWindow()

        try await assertSearchFindsEvidence(fixture, path: path, query: "DISCOVERY_AFTER_FIRST_40KB")
    }

    func testWholeCodebaseSearchRetainsEarlierMatchesWhenUTF8ScalarCrossesByteWindow() async throws {
        let fixture = try VyronLargeCodebaseAnalysisFixture(sourceCount: 8)
        defer { fixture.cleanUp() }
        await fixture.prepare()
        let path = try await fixture.plantEvidenceBeforeSplitUTF8Scalar()

        try await assertSearchFindsEvidence(fixture, path: path, query: "DISCOVERY_BEFORE_SPLIT_UTF8")
    }

    private func exerciseNearLimitPrompt(mode: ComposerMode) async throws {
        let fixture = try VyronLargeCodebaseAnalysisFixture()
        defer { fixture.cleanUp() }
        await fixture.prepare(mode: mode)
        let paragraph = "Review architecture, cancellation and bounded state; inspect evidence. "
            + "İncele, gözlemle. 検証する。\n"
        let padding = String(repeating: paragraph, count: 590)
        let prompt = """
        REQUIREMENT_BEGIN: Analyze the codebase and identify improvements without editing any project files.
        \(padding)
        REQUIREMENT_MIDDLE: Retain this central requirement: report the source path for every finding.
        \(padding)
        REQUIREMENT_END: State the bounded reviewed scope and distinguish observations from recommendations.
        """
        XCTAssertGreaterThan(prompt.utf8.count, 100_000)
        XCTAssertLessThanOrEqual(prompt.utf8.count, VyronDevelopmentTaskLimits.maximumGoalBytes)
        fixture.test.model.composer.draft = prompt
        XCTAssertTrue(fixture.test.model.canSend)
        fixture.test.model.send()
        try await fixture.test.waitUntil { !fixture.test.model.foregroundRun.isGenerating }

        XCTAssertEqual(
            fixture.test.model.messages.first { $0.conversationRole == .user }?.developmentTaskFilename,
            "task-description.txt"
        )
        let restored = try fixture.test.model.historyStore.load()
        XCTAssertEqual(restored.first?.messages.first { $0.conversationRole == .user }?.content, prompt)
        try await assertCompletedAudit(fixture, prompt: prompt, mode: mode == .plan ? .plan : .agent)
    }

    private func assertSearchFindsEvidence(
        _ fixture: VyronLargeCodebaseAnalysisFixture,
        path: String,
        query: String
    ) async throws {
        let workspace = try XCTUnwrap(fixture.test.model.workspaceState.developmentWorkspace)
        let results = try await workspace.search(query: query, limit: 40)
        try fixture.assertSourceUnchanged()
        guard let match = results.split(separator: "\n").first(where: { $0.contains(query) }) else {
            XCTFail("Native project search did not expose \(query) in \(path). Actual result: \(results)")
            return
        }
        XCTAssertTrue(match.contains("\(path):"), "Evidence must retain its source path")
    }

    private func assertCompletedAudit(
        _ fixture: VyronLargeCodebaseAnalysisFixture,
        prompt: String,
        mode: DevelopmentMode = .plan
    ) async throws {
        XCTAssertEqual(fixture.test.model.messages.first { $0.conversationRole == .user }?.content, prompt)
        try fixture.assertSourceUnchanged()
        let requests = await fixture.provider.requests
        guard requests.count >= 5 else {
            let failure = fixture.test.model.errorMessage ?? "No application error was reported"
            XCTFail("Accepted \(prompt.utf8.count)-byte \(mode.rawValue) audit reached \(requests.count) of five "
                + "required offline inference steps. Failure: \(failure)")
            return
        }
        let modes = await fixture.provider.modes
        let models = await fixture.provider.requestedModels
        let markers = await fixture.provider.observedGoalMarkers
        let early = await fixture.provider.sawEarlyEvidence
        let late = await fixture.provider.sawLateEvidence
        let leaked = await fixture.provider.leakedExcludedEvidence
        XCTAssertTrue(modes.allSatisfy { $0 == mode })
        XCTAssertTrue(models.allSatisfy { $0 == "qwen3-coder:30b" })
        XCTAssertEqual(markers, Set(VyronLargeCodebaseAnalysisFixture.goalMarkers))
        XCTAssertTrue(early)
        XCTAssertTrue(late)
        XCTAssertFalse(leaked)
        XCTAssertEqual(fixture.test.model.messages.last?.activity?.state, .completed)
        XCTAssertTrue(fixture.test.model.messages.last?.content.contains("not an exhaustive review") == true)
        XCTAssertTrue(fixture.test.model.messages.last?.content.contains("Sources/Feature599.swift:5") == true)
        XCTAssertNil(fixture.test.model.errorMessage)
    }
}
