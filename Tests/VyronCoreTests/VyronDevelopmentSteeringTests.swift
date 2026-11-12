import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

final class VyronDevelopmentSteeringTests: XCTestCase, @unchecked Sendable {
    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronSteering-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }

    private func externalTool() -> DevelopmentExternalTool {
        DevelopmentExternalTool(
            name: "mcp_fixture_write",
            description: "Write a fixture resource",
            inputSchema: ["type": .string("object")],
            isReadOnly: false
        )
    }

    func testInboxPreservesOrderAndAtomicallyRefusesLateMessages() async {
        let inbox = VyronSteeringInbox()
        let first = VyronSteeringMessage(content: "Keep the existing layout.")
        let second = VyronSteeringMessage(content: "Only update the text.")
        let acceptedFirst = await inbox.append(first)
        let acceptedSecond = await inbox.append(second)
        let drained = await inbox.drain(finishingIfEmpty: true)
        XCTAssertTrue(acceptedFirst)
        XCTAssertTrue(acceptedSecond)
        XCTAssertEqual(drained, [first, second])

        let acceptedBeforeCompletion = await inbox.append(first)
        XCTAssertTrue(acceptedBeforeCompletion, "A nonempty drain must keep the run open")
        _ = await inbox.drain()
        let completion = await inbox.drain(finishingIfEmpty: true)
        let acceptedAfterCompletion = await inbox.append(second)
        XCTAssertTrue(completion.isEmpty)
        XCTAssertFalse(acceptedAfterCompletion)
    }

    func testUpdateArrivingWithFinalReplyReplansBeforeCompleting() async throws {
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Keep this change in the desktop package.")
        let applied = VyronSteeringTestLog<VyronSteeringMessage>()
        let provider = VyronSteeringTestProvider { round, _ in
            if round == 1 {
                await inbox.append(update)
                return DevelopmentMessage(role: "assistant", content: "Obsolete result")
            }
            return DevelopmentMessage(role: "assistant", content: "Updated desktop result")
        }
        let result = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Review a focused change", model: "fixture-coder", steeringInbox: inbox,
            onSteeringApplied: { applied.append($0) }, onEvent: { _ in }, approveCommand: { _ in false }
        )
        let requests = await provider.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].suffix(2).map(\.content), ["Obsolete result", update.content])
        XCTAssertEqual(applied.values, [update])
        XCTAssertTrue(result.finalMessage.contains("Updated desktop result"))
        let acceptedLate = await inbox.append(update)
        XCTAssertFalse(acceptedLate)
    }

    func testUpdateDuringInferenceSkipsAllStaleToolsWithMatchingCallIDs() async throws {
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Inspect only; do not write anything.")
        let calls = ["first", "second"].map {
            DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: $0)
        }
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let provider = VyronSteeringTestProvider { round, _ in
            if round == 1 {
                await inbox.append(update)
                return DevelopmentMessage(role: "assistant", toolCalls: calls)
            }
            return DevelopmentMessage(role: "assistant", content: "Read-only result")
        }
        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Review a resource", model: "fixture-coder", externalTools: [externalTool()],
            executeExternalTool: { call in
                executed.append(call)
                return DevelopmentExternalResult(text: "Written")
            },
            steeringInbox: inbox, onEvent: { _ in }, approveCommand: { _ in false }
        )
        let requests = await provider.recordedRequests()
        let responses = requests[1].filter { $0.role == "tool" }
        XCTAssertTrue(executed.values.isEmpty)
        XCTAssertEqual(responses.map(\.toolCallID), ["first", "second"])
        XCTAssertTrue(responses.allSatisfy { $0.content.contains("Not executed") })
        XCTAssertEqual(requests[1].last?.content, update.content)
    }

    func testUpdateDuringExternalToolRetainsCompletedResultAndSkipsRemainingTools() async throws {
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Do not create another resource.")
        let calls = ["completed", "stale"].map {
            DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: $0)
        }
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let provider = VyronSteeringTestProvider { round, _ in
            if round == 1 { return DevelopmentMessage(role: "assistant", toolCalls: calls) }
            return DevelopmentMessage(role: "assistant", content: "One resource was created")
        }
        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Create resources", model: "fixture-coder", externalTools: [externalTool()],
            executeExternalTool: { call in
                executed.append(call)
                await inbox.append(update)
                return DevelopmentExternalResult(text: "Created resource exact-id")
            },
            steeringInbox: inbox, onEvent: { _ in }, approveCommand: { _ in false }
        )
        let requests = await provider.recordedRequests()
        let responses = requests[1].filter { $0.role == "tool" }
        XCTAssertEqual(executed.values, [calls[0]])
        XCTAssertEqual(responses.map(\.toolCallID), ["completed", "stale"])
        XCTAssertTrue(responses[0].content.contains("Created resource exact-id"))
        XCTAssertTrue(responses[0].content.contains("\"ok\":true"))
        XCTAssertTrue(responses[1].content.contains("Not executed"))
        XCTAssertEqual(requests[1].last?.content, update.content)
    }

    func testUpdateDuringCommandReviewPreventsCommandFromStarting() async throws {
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Skip this command and describe the result.")
        let call = DevelopmentToolCall(
            name: "run_command", arguments: ["command": .string("/usr/bin/false")], id: "reviewed-command"
        )
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1
                ? DevelopmentMessage(role: "assistant", toolCalls: [call])
                : DevelopmentMessage(role: "assistant", content: "The command was skipped")
        }
        let result = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Review a local command", model: "fixture-coder", steeringInbox: inbox,
            onEvent: { _ in }, approveCommand: { _ in
                await inbox.append(update)
                return true
            }
        )
        let requests = await provider.recordedRequests()
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertEqual(requests[1].first(where: { $0.role == "tool" })?.toolCallID, call.id)
        XCTAssertEqual(requests[1].last?.content, update.content)
    }

    func testCancellationDuringExternalToolDoesNotRetryOrAcknowledgePendingUpdate() async throws {
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Change direction after this tool.")
        let applied = VyronSteeringTestLog<VyronSteeringMessage>()
        let executed = VyronSteeringTestLog<DevelopmentToolCall>()
        let call = DevelopmentToolCall(name: "mcp_fixture_write", arguments: [:], id: "uncertain-result")
        let provider = VyronSteeringTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", toolCalls: [call])
        }
        do {
            _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
                goal: "Create a resource", model: "fixture-coder", externalTools: [externalTool()],
                executeExternalTool: { call in
                    executed.append(call)
                    await inbox.append(update)
                    throw CancellationError()
                },
                steeringInbox: inbox, onSteeringApplied: { applied.append($0) },
                onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("Cancellation must propagate")
        } catch is CancellationError {
            let requests = await provider.recordedRequests()
            let pending = await inbox.drain()
            XCTAssertEqual(executed.values, [call])
            XCTAssertEqual(requests.count, 1)
            XCTAssertTrue(applied.values.isEmpty)
            XCTAssertEqual(pending, [update])
        }
    }

    func testCancellationDuringAcknowledgmentPreventsAnotherModelRequest() async throws {
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Use the revised requirement.")
        let applied = VyronSteeringTestLog<VyronSteeringMessage>()
        let provider = VyronSteeringTestProvider { _, _ in
            await inbox.append(update)
            return DevelopmentMessage(role: "assistant", content: "Initial result")
        }
        let agent = try DevelopmentAgent(client: provider, workspace: workspace())
        let execution = Task {
            try await agent.run(
                goal: "Review a change", model: "fixture-coder", steeringInbox: inbox,
                onSteeringApplied: { update in
                    applied.append(update)
                    withUnsafeCurrentTask { $0?.cancel() }
                },
                onEvent: { _ in }, approveCommand: { _ in false }
            )
        }
        do {
            _ = try await execution.value
            XCTFail("Cancellation during acknowledgment must stop before the provider request")
        } catch is CancellationError {
            let requests = await provider.recordedRequests()
            XCTAssertEqual(requests.count, 1)
            XCTAssertEqual(applied.values, [update])
        }
    }

    func testContextTruncationRetainsSteeringWhileDroppingOlderToolExchanges() throws {
        let base = [DevelopmentMessage(role: "system", content: "Rules")]
        let old = DevelopmentExchange(messages: [DevelopmentMessage(role: "assistant", content: String(repeating: "x", count: 500))])
        let update = DevelopmentExchange(messages: [DevelopmentMessage(role: "user", content: "Do not modify shared code.")])
        let latest = DevelopmentExchange(messages: [DevelopmentMessage(role: "assistant", content: "Latest completed step")])
        let expected = base + update.messages + latest.messages
        let budget = try JSONEncoder().encode(expected).count
        let retained = try boundedDevelopmentMessages(base: base, exchanges: [old, update, latest], maximumBytes: budget)
        XCTAssertEqual(retained, expected)
    }

    func testOversizedSteeringFailsBeforeAcknowledgmentOrAnotherRequest() async throws {
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: String(repeating: "x", count: 30_000))
        let applied = VyronSteeringTestLog<VyronSteeringMessage>()
        let provider = VyronSteeringTestProvider { _, _ in
            await inbox.append(update)
            return DevelopmentMessage(role: "assistant", content: "Initial result")
        }
        do {
            _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
                goal: "Review a change", model: "fixture-coder", steeringInbox: inbox,
                onSteeringApplied: { applied.append($0) }, onEvent: { _ in }, approveCommand: { _ in false }
            )
            XCTFail("Unbounded guidance must not exceed the local context budget")
        } catch DevelopmentAgentError.contextBudget {
            let requests = await provider.recordedRequests()
            XCTAssertEqual(requests.count, 1)
            XCTAssertTrue(applied.values.isEmpty)
        }
    }
}
