import Foundation
import XCTest
import VyronDevelopment
import VyronModelDomain
@testable import VyronCore

@MainActor
final class VyronDevelopmentAdaptiveBudgetLifecycleTests: XCTestCase {
    func testBudgetUsesTheResolvedModelAndUltraBeforeStartingInference() async throws {
        let workspace = try workspace()
        let provider = VyronAdaptiveBudgetTestProvider(budget: { _ in
            .init(workingBytes: 50_000, maximumBytes: 60_000)
        })
        let result = try await DevelopmentAgent(client: provider, workspace: workspace).run(
            goal: "Inspect the code without editing", model: "requested-model", effort: .ultra,
            mode: .plan, onEvent: { _ in }, approveCommand: { _ in false }
        )
        let requests = await provider.requests
        let count = await provider.inferenceCount
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.model.name, "selected-coder")
        XCTAssertEqual(requests.first?.configuration.effort, .ultra)
        XCTAssertGreaterThan(try XCTUnwrap(requests.first).minimumMessageBytes, 1_000)
        XCTAssertEqual(count, 1)
        XCTAssertTrue(result.isComplete)
    }

    func testBudgetFailureAndCancellationNeverDispatchInference() async throws {
        let workspace = try workspace()
        let failed = VyronAdaptiveBudgetTestProvider(budget: { _ in throw DevelopmentAgentError.contextBudget })
        let cancelled = VyronAdaptiveBudgetTestProvider(budget: { _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return .init(workingBytes: 50_000, maximumBytes: 60_000)
        })
        for (provider, expectsCancellation) in [(failed, false), (cancelled, true)] {
            let task = Task {
                try await DevelopmentAgent(client: provider, workspace: workspace).run(
                    goal: "Inspect the code", model: "requested-model", effort: .ultra,
                    mode: .plan, onEvent: { _ in }, approveCommand: { _ in false }
                )
            }
            do {
                _ = try await task.value
                XCTFail("A rejected or cancelled budget must stop before inference")
            } catch {
                if expectsCancellation { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertEqual(error as? DevelopmentAgentError, .contextBudget) }
            }
            let count = await provider.inferenceCount
            XCTAssertEqual(count, 0)
        }
    }

    func testFolderRemovedDuringBudgetLookupDoesNotBecomeTheActiveProject() async throws {
        let workspace = try workspace()
        let destination = workspace.rootURL.appendingPathComponent("Destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let calls = VyronSteeringTestLog<Int>()
        let opened = VyronSteeringTestLog<DevelopmentWorkspace>()
        let provider = VyronAdaptiveBudgetTestProvider { request in
            calls.append(request.minimumMessageBytes)
            if calls.values.count == 2 { try FileManager.default.removeItem(at: destination) }
            return .init(workingBytes: 50_000, maximumBytes: 60_000)
        } step: { round, _ in
            if round == 1 {
                return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                    name: "open_project_folder", arguments: ["path": .string(destination.path)]
                )])
            }
            return DevelopmentMessage(role: "assistant", content: "The folder disappeared; the current project remains active.")
        }
        let agent = DevelopmentAgent(client: provider, workspace: workspace)
        try await agent.configureFolderAccess(VyronDevelopmentFolderAccess(
            approveCreation: { _ in true }, openProject: { opened.append($0) }
        ))
        _ = try await agent.run(
            goal: "Move this conversation to the requested folder.", model: "requested-model", effort: .ultra,
            onEvent: { _ in }, approveCommand: { _ in true }
        )
        XCTAssertEqual(calls.values.count, 2)
        XCTAssertTrue(opened.values.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VyronBudgetLifecycle-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }
}
