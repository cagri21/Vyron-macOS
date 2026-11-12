import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronParallelTaskTests: XCTestCase {
    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronParallel-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }

    private func parallelCall(count: Int = 3) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "parallel_tasks", arguments: [
            "tasks": .array((1...count).map { index in
                .object(["name": .string("Task \(index)"), "prompt": .string("Inspect topic \(index)")])
            })
        ], id: "parallel-call")
    }

    func testStrictNativeSchemaRejectsUnboundedOrAmbiguousTasks() throws {
        XCTAssertEqual(try VyronParallelTaskTool.decode(parallelCall()).count, 3)
        let invalid: [[DevelopmentJSONValue]] = [
            [],
            Array(repeating: .object(["name": .string("Same"), "prompt": .string("Inspect")]), count: 4),
            [.object(["name": .string("A"), "prompt": .string(" ")])],
            [.object(["name": .string("A"), "prompt": .string("Inspect"), "mode": .string("agent")])],
            [.object(["name": .string("A"), "prompt": .string("Inspect")]),
             .object(["name": .string("a"), "prompt": .string("Inspect another")])]
        ]
        for values in invalid {
            XCTAssertThrowsError(try VyronParallelTaskTool.decode(DevelopmentToolCall(
                name: "parallel_tasks", arguments: ["tasks": .array(values)]
            )))
        }
    }

    func testHelpersActuallyRunConcurrentlyAndParentReceivesEveryFinding() async throws {
        let call = parallelCall()
        let concurrency = VyronParallelTestConcurrency()
        let events = VyronSteeringTestLog<VyronSubagentEvent>()
        let provider = VyronParallelTestProvider { request in
            if request.mode == .agent {
                return request.messages.last?.role == "tool"
                    ? DevelopmentMessage(role: "assistant", content: "Integrated all three findings.")
                    : DevelopmentMessage(role: "assistant", toolCalls: [call])
            }
            await concurrency.enter()
            try await Task.sleep(for: .milliseconds(80))
            await concurrency.leave()
            return DevelopmentMessage(role: "assistant", content: "Read-only finding for this topic.")
        }
        let result = try await DevelopmentAgent(
            client: provider, workspace: workspace(), onSubagentEvent: { events.append($0) }
        ).run(goal: "Coordinate research", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false })
        let peak = await concurrency.maximum()
        let requests = await provider.recordedRequests()
        XCTAssertEqual(peak, 3)
        XCTAssertEqual(requests.filter { $0.mode == .plan }.count, 3)
        XCTAssertTrue(requests.filter { $0.mode == .plan }.allSatisfy { $0.tools.isEmpty })
        XCTAssertTrue(requests.allSatisfy { $0.model == "fixture-coder" })
        XCTAssertTrue(requests.first?.tools.contains("parallel_tasks") == true)
        let parentReply = try XCTUnwrap(requests.last?.messages.last { $0.role == "tool" })
        let envelope = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(parentReply.content.utf8))
        guard case .string(let output) = envelope["output"],
            case .array(let findings) = try JSONDecoder().decode(DevelopmentJSONValue.self, from: Data(output.utf8))
        else { return XCTFail("Every helper must produce a structured finding") }
        XCTAssertEqual(findings.count, 3)
        XCTAssertEqual(events.values.filter { if case .started = $0.update { return true }; return false }.count, 3)
        XCTAssertEqual(events.values.filter { if case .finished = $0.update { return true }; return false }.count, 3)
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertTrue(result.finalMessage.contains("Integrated"))
    }

    func testChildCannotEditRunCommandsOrDelegateAgain() async throws {
        let call = parallelCall(count: 1)
        let events = VyronSteeringTestLog<VyronSubagentEvent>()
        let write = DevelopmentToolCall(name: "write_file", arguments: [
            "path": .string("forbidden.txt"), "content": .string("No")
        ], id: "child-write")
        let command = DevelopmentToolCall(name: "run_command", arguments: [
            "command": .string("/usr/bin/false")
        ], id: "child-command")
        let provider = VyronParallelTestProvider { request in
            if request.mode == .agent {
                return request.messages.last?.role == "tool"
                    ? DevelopmentMessage(role: "assistant", content: "The helper stayed read-only.")
                    : DevelopmentMessage(role: "assistant", toolCalls: [call])
            }
            return request.messages.last?.role == "tool"
                ? DevelopmentMessage(role: "assistant", content: "I cannot perform those operations.")
                : DevelopmentMessage(role: "assistant", toolCalls: [write, command, call])
        }
        let project = try workspace()
        _ = try await DevelopmentAgent(client: provider, workspace: project, onSubagentEvent: { events.append($0) })
            .run(goal: "Coordinate", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false })
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.rootURL.appendingPathComponent("forbidden.txt").path))
        let requests = await provider.recordedRequests()
        let childResponses = requests.filter { $0.mode == .plan }.last?.messages.filter { $0.role == "tool" } ?? []
        XCTAssertEqual(childResponses.count, 3)
        XCTAssertTrue(childResponses.allSatisfy { $0.content.contains("\"ok\":false") })
        XCTAssertEqual(events.values.filter { if case .started = $0.update { return true }; return false }.count, 1)
    }

    func testOneFailedHelperDoesNotCancelSuccessfulSiblings() async throws {
        let call = parallelCall()
        let events = VyronSteeringTestLog<VyronSubagentEvent>()
        let provider = VyronParallelTestProvider { request in
            if request.mode == .agent {
                return request.messages.last?.role == "tool"
                    ? DevelopmentMessage(role: "assistant", content: "Two findings and one failure were reported.")
                    : DevelopmentMessage(role: "assistant", toolCalls: [call])
            }
            if request.messages.last?.content.contains("Inspect topic 2") == true {
                throw ModelProviderError.invalidResponse("Fixture failure")
            }
            return DevelopmentMessage(role: "assistant", content: "Successful finding")
        }
        _ = try await DevelopmentAgent(client: provider, workspace: workspace(), onSubagentEvent: { events.append($0) })
            .run(goal: "Coordinate", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false })
        let states = events.values.compactMap { event -> ResponseActivity.State? in
            if case .finished(let completion) = event.update { return completion.state }
            return nil
        }
        XCTAssertEqual(states.filter { $0 == .completed }.count, 2)
        XCTAssertEqual(states.filter { $0 == .failed }.count, 1)
    }

    func testParentStopCancelsAllHelpersWithoutAnotherParentRequest() async throws {
        let call = parallelCall()
        let started = expectation(description: "All helpers entered inference")
        started.expectedFulfillmentCount = 3
        let events = VyronSteeringTestLog<VyronSubagentEvent>()
        let provider = VyronParallelTestProvider { request in
            if request.mode == .agent { return DevelopmentMessage(role: "assistant", toolCalls: [call]) }
            started.fulfill()
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        }
        let agent = try DevelopmentAgent(
            client: provider, workspace: workspace(), onSubagentEvent: { events.append($0) }
        )
        let execution = Task {
            try await agent.run(
                goal: "Coordinate", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false }
            )
        }
        let readiness = await XCTWaiter.fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(readiness, .completed)
        execution.cancel()
        do {
            _ = try await execution.value
            XCTFail("Stop must cancel parent and helpers")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let states = events.values.compactMap { event -> ResponseActivity.State? in
            if case .finished(let completion) = event.update { return completion.state }
            return nil
        }
        XCTAssertEqual(states, [.stopped, .stopped, .stopped])
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.filter { $0.mode == .agent }.count, 1)
    }

    func testTightResultBudgetRetainsEveryOutcomeInTaskOrder() throws {
        let results = (1...3).map { index in
            VyronParallelTaskResult(
                identity: VyronSubagentIdentity(name: "Task \(index)", prompt: "Inspect", model: "fixture-coder"),
                completion: VyronSubagentCompletion(state: .completed, summary: String(repeating: "\\\"я", count: 2_000))
            )
        }
        let response = try VyronParallelTaskRunner.response(results, maximumBytes: 512)
        XCTAssertLessThanOrEqual(response.utf8.count, 512)
        let envelope = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: Data(response.utf8))
        XCTAssertEqual(envelope["truncated"], .bool(false))
        guard case .string(let output) = envelope["output"],
            case .array(let values) = try JSONDecoder().decode(DevelopmentJSONValue.self, from: Data(output.utf8))
        else { return XCTFail("Results must remain valid JSON") }
        XCTAssertEqual(values.count, 3)
        for (index, value) in values.enumerated() {
            guard case .object(let fields) = value else { return XCTFail("Missing helper result") }
            XCTAssertEqual(fields["task"], .number(Double(index + 1)))
            XCTAssertEqual(fields["truncated"], .bool(true))
            XCTAssertEqual(fields["state"], .string("completed"))
        }
    }

    func testThreeHelperBudgetCannotBeExceededAcrossBatches() async throws {
        let call = parallelCall()
        let events = VyronSteeringTestLog<VyronSubagentEvent>()
        let provider = VyronParallelTestProvider { request in
            guard request.mode == .agent else { return DevelopmentMessage(role: "assistant", content: "Finding") }
            if request.messages.last?.content.contains("budget is exhausted") == true {
                return DevelopmentMessage(role: "assistant", content: "The helper budget was respected.")
            }
            return DevelopmentMessage(role: "assistant", toolCalls: [call])
        }
        _ = try await DevelopmentAgent(client: provider, workspace: workspace(), onSubagentEvent: { events.append($0) })
            .run(goal: "Coordinate", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false })
        XCTAssertEqual(events.values.filter { if case .started = $0.update { return true }; return false }.count, 3)
    }

    func testParentReadScopeSurvivesHelpersAndDelegationBatchDefersEdits() async throws {
        let call = parallelCall(count: 1)
        let project = try workspace()
        try "Before".write(to: project.rootURL.appendingPathComponent("value.txt"), atomically: true, encoding: .utf8)
        let read = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("value.txt")])
        let edit = DevelopmentToolCall(name: "edit_file", arguments: [
            "path": .string("value.txt"), "old_text": .string("Before"), "new_text": .string("After")
        ], id: "parent-edit")
        let premature = DevelopmentToolCall(name: "write_file", arguments: [
            "path": .string("premature.txt"), "content": .string("No")
        ], id: "premature-write")
        let provider = VyronParallelTestProvider { request in
            guard request.mode == .agent else { return DevelopmentMessage(role: "assistant", content: "Finding") }
            switch request.messages.last?.toolName {
            case "read_file": return DevelopmentMessage(role: "assistant", toolCalls: [premature, call])
            case "parallel_tasks": return DevelopmentMessage(role: "assistant", toolCalls: [edit])
            case "edit_file": return DevelopmentMessage(role: "assistant", content: "Applied the focused change.")
            default: return DevelopmentMessage(role: "assistant", toolCalls: [read])
            }
        }
        let result = try await DevelopmentAgent(client: provider, workspace: project, onSubagentEvent: { _ in })
            .run(goal: "Coordinate", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false })
        XCTAssertEqual(result.changedFiles, ["value.txt"])
        XCTAssertEqual(try String(contentsOf: project.rootURL.appendingPathComponent("value.txt"), encoding: .utf8), "After")
        XCTAssertFalse(FileManager.default.fileExists(atPath: project.rootURL.appendingPathComponent("premature.txt").path))
    }

    func testHelpersReceiveLatestSteeringConstraints() async throws {
        let call = parallelCall(count: 1)
        let inbox = VyronSteeringInbox()
        let guidance = VyronSteeringMessage(content: "Inspect only Sources/Public; avoid the internal folder.")
        let provider = VyronParallelTestProvider { request in
            guard request.mode == .agent else { return DevelopmentMessage(role: "assistant", content: "Finding") }
            if !request.messages.contains(where: { $0.role == "user" && $0.content == guidance.content }) {
                await inbox.append(guidance)
                return DevelopmentMessage(role: "assistant", content: "This earlier answer needs the update.")
            }
            return request.messages.last?.role == "tool"
                ? DevelopmentMessage(role: "assistant", content: "The revised constraints were retained.")
                : DevelopmentMessage(role: "assistant", toolCalls: [call])
        }
        _ = try await DevelopmentAgent(client: provider, workspace: workspace(), onSubagentEvent: { _ in }).run(
            goal: "Coordinate", model: "fixture-coder", steeringInbox: inbox,
            onEvent: { _ in }, approveCommand: { _ in false }
        )
        let requests = await provider.recordedRequests()
        let child = try XCTUnwrap(requests.first { $0.mode == .plan })
        XCTAssertTrue(child.messages.contains { $0.role == "user" && $0.content.contains(guidance.content) })
    }
}
