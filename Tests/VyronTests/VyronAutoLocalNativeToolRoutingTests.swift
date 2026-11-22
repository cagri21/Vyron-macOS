import Foundation
import XCTest
import VyronModelDomain
@testable import Vyron

@MainActor
final class VyronAutoLocalNativeToolRoutingTests: XCTestCase {
    func testAdvertisedButUnsupportedLocalToolsAreRejectedBeforeWorkAndAnotherCandidateIsAssessed() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        try await prepareWork(test)
        let unsupported = "imported-reasoner:8b"
        let supported = "imported-tools:12b"
        test.model.modelSelection.models += [model(unsupported), model(supported)]
        test.model.composer.effort = .ultra
        await test.local.rejectNativeTools(for: [unsupported])
        await test.assessment.selectSequence([unsupported, supported])

        test.send("Run the requested release command with a real native tool call.")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let checks = await test.local.nativeChecks
        let models = await test.local.developmentModels
        let assessments = await test.assessment.requests
        let efforts = await test.local.efforts
        XCTAssertEqual(checks, [unsupported, supported])
        XCTAssertEqual(models, [supported])
        XCTAssertEqual(assessments.count, 2)
        XCTAssertFalse(assessments[1].candidates.contains { $0.id == unsupported })
        XCTAssertEqual(efforts, [.ultra])
        XCTAssertTrue(test.model.modelSelection.isAutoLocalEnabled)
        XCTAssertEqual(test.model.modelSelection.selectedModel, "qwen3:4b")
        let configuration = try XCTUnwrap(test.model.autoLocalConfiguration())
        XCTAssertFalse(test.model.autoLocalCandidates(configuration, requiresTools: true).contains { $0.id == unsupported })
        XCTAssertTrue(test.model.autoLocalCandidates(configuration, requiresTools: false).contains { $0.id == unsupported })
        XCTAssertNil(test.model.modelRanking.score(for: unsupported))
        XCTAssertTrue(test.model.modelRanking.otherModels.contains { $0.name == unsupported })
    }

    func testUnsupportedCandidateFallbackHasABoundedAttemptAllowance() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        try await prepareWork(test)
        let names = ["first:8b", "second:8b", "third:8b", "fourth:8b"]
        test.model.modelSelection.models += names.map(model)
        await test.local.rejectNativeTools(for: Set(names))
        await test.assessment.selectSequence(names)

        test.send("Perform the requested native project action.")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let checks = await test.local.nativeChecks
        let work = await test.local.developmentModels
        XCTAssertEqual(checks, Array(names.prefix(3)))
        XCTAssertTrue(work.isEmpty)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .failed)
    }

    func testChatKeepsAnImportedReasonerWithoutRunningAToolProbe() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        let name = "imported-reasoner:8b"
        test.model.modelSelection.models += [model(name)]
        await test.local.rejectNativeTools(for: [name])
        await test.assessment.select(name)

        test.send("Explain the release process without performing actions.")
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let checks = await test.local.nativeChecks
        let chat = await test.local.chatModels
        XCTAssertTrue(checks.isEmpty)
        XCTAssertEqual(chat, [name])
    }

    func testStopDuringNativeCheckCannotPublishLateVerificationOrStartWork() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        try await prepareWork(test)
        let name = "imported-tools:12b"
        test.model.modelSelection.models += [model(name)]
        await test.assessment.select(name)
        await test.local.holdNativeChecks()

        test.send("Run the requested native project action.")
        try await test.waitUntil { await test.local.nativeChecks.count == 1 }
        test.model.stopGeneration()
        let pending = test.model.foregroundRun.shutdown()
        await test.local.releaseNativeChecks()
        for task in pending { await task.value }

        let work = await test.local.developmentModels
        XCTAssertTrue(work.isEmpty)
        XCTAssertFalse(test.model.modelFeatures.toolChecks.contains {
            $0.selection.modelName == name && $0.result == .verified
        })
        XCTAssertEqual(test.model.messages.last?.activity?.state, .stopped)
    }

    private func prepareWork(_ test: VyronAutoLocalAppTestHarness) async throws {
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .agent
    }

    private func model(_ name: String) -> LocalModel {
        LocalModel(name: name, size: 8_000_000_000, capabilities: ["completion", "tools", "thinking"])
    }
}
