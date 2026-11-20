import Foundation
import XCTest
import VyronCore
import VyronModelDomain
@testable import Vyron

@MainActor
final class VyronCodeInspectionRoutingTests: XCTestCase {
    private let coder = "qwen3-coder:30b"
    private let source = "func normalize(_ value: String) -> String { value.trimmingCharacters(in: .whitespaces) }\n"

    func testWorkCodeInspectionUsesSourceOnlyNativePlanWithoutChangingVisibleWorkModelEffortOrGoal() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        let project = try await prepare(test, mode: .agent)
        test.model.composer.effort = .ultra
        let selectedModel = test.model.modelSelection.selectedModel
        let goal = "analyze the code"

        test.send(goal)
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let modes = await test.local.developmentModes
        let tools = await test.local.externalToolNames
        let models = await test.local.developmentModels
        let requests = await test.local.developmentRequests
        let efforts = await test.local.efforts
        let selections = await test.local.automaticSelections
        let assessment = await test.assessment.requests
        let builds = await test.assessment.providerBuilds

        XCTAssertEqual(modes, [.plan])
        XCTAssertEqual(models, [coder])
        XCTAssertEqual(efforts.first, .ultra)
        XCTAssertEqual(selections, [false])
        XCTAssertTrue(builds.isEmpty)
        XCTAssertEqual(assessment.count, 1)
        XCTAssertTrue(try XCTUnwrap(assessment.first).context.requiresTools)
        XCTAssertEqual(try XCTUnwrap(assessment.first).context.messages.last?.content, goal)
        let messages = try XCTUnwrap(requests.first)
        XCTAssertTrue(messages.contains { $0.role == "user" && $0.content == goal })
        let catalog = Set(try XCTUnwrap(tools.first))
        XCTAssertTrue(catalog.isSubset(of: ["parallel_tasks", "read_skill_resource"]), catalog.sorted().joined(separator: ", "))
        XCTAssertFalse(catalog.contains { $0.hasPrefix("vyron_mac_") })
        XCTAssertFalse(catalog.contains { $0.hasPrefix("office_") })
        XCTAssertFalse(catalog.contains("web_search"))
        XCTAssertFalse(catalog.contains("read_web_page"))
        XCTAssertEqual(test.model.composer.mode, .agent)
        XCTAssertEqual(test.model.composer.effort, .ultra)
        XCTAssertEqual(test.model.modelSelection.selectedModel, selectedModel)
        XCTAssertTrue(test.model.modelSelection.isAutoLocalEnabled)
        XCTAssertEqual(test.model.messages.first { $0.role == "user" }?.content, goal)
        XCTAssertEqual(test.model.messages.last?.content, "Auto Local work answer")
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
        XCTAssertTrue(test.model.inspector.developmentChanges.isEmpty)
        XCTAssertFalse(test.model.computerWork.isComputerWorkActive)
        XCTAssertNil(test.model.computerWork.pendingAgentGoal)
        XCTAssertEqual(try String(contentsOf: project.appendingPathComponent("Source.swift"), encoding: .utf8), source)
        let conversation = try XCTUnwrap(test.model.conversations.first { $0.id == test.model.selectedConversationID })
        XCTAssertEqual(conversation.mode, ComposerMode.agent.rawValue)
    }

    func testMixedInspectionAndFixKeepsNativeWorkAndItsExistingActionCatalog() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        _ = try await prepare(test, mode: .agent)
        let goal = "analyze the code and fix the bug"

        test.send(goal)
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let modes = await test.local.developmentModes
        let catalogs = await test.local.externalToolNames
        let requests = await test.local.developmentRequests

        XCTAssertEqual(modes, [.agent])
        XCTAssertEqual(test.model.composer.mode, .agent)
        let catalog = Set(try XCTUnwrap(catalogs.first))
        let existingTools = VyronWebTools.definitions + VyronOfficeTools.definitions
            + VyronMacWorkRun.definitions + VyronChromeTools.definitions
        XCTAssertTrue(Set(existingTools.map(\.name)).isSubset(of: catalog))
        XCTAssertTrue(try XCTUnwrap(requests.first).contains { $0.role == "user" && $0.content == goal })
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    func testExplicitPlanRemainsPlanWhenTheRequestAlsoAsksForAFix() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        _ = try await prepare(test, mode: .plan)
        let goal = "analyze the code and fix the bug"

        test.send(goal)
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }
        let modes = await test.local.developmentModes
        let catalogs = await test.local.externalToolNames
        let requests = await test.local.developmentRequests

        XCTAssertEqual(modes, [.plan])
        XCTAssertEqual(test.model.composer.mode, .plan)
        let catalog = Set(try XCTUnwrap(catalogs.first))
        XCTAssertTrue(catalog.contains("office_status"), "A non-inspection Plan keeps its existing read-only integrations")
        XCTAssertFalse(catalog.contains("office_render"))
        XCTAssertTrue(try XCTUnwrap(requests.first).contains { $0.role == "user" && $0.content == goal })
        XCTAssertEqual(test.model.messages.last?.activity?.state, .completed)
    }

    private func prepare(_ test: VyronAutoLocalAppTestHarness, mode: ComposerMode) async throws -> URL {
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data(source.utf8).write(to: project.appendingPathComponent("Source.swift"))
        await test.model.loadWorkspace(project)
        test.model.modelSelection.models.append(LocalModel(
            name: coder, size: 19_000_000_000, capabilities: ["completion", "tools"]
        ))
        await test.assessment.select(coder)
        test.model.composer.mode = mode
        XCTAssertNil(test.model.errorMessage)
        return project
    }
}
