import Foundation
import XCTest
import VyronDevelopment
import VyronLocalization
@testable import VyronCore

@MainActor
final class VyronProjectApprovalModeTests: XCTestCase {
    func testModesPreserveClassifiedReasonsAndAddReviewForRoutineCommandsWhenRequested() {
        let classifiedReason = "Review this unfamiliar project command."
        XCTAssertEqual(
            VyronProjectApprovalMode.askForApproval.commandReviewReason(for: nil),
            VyronProjectApprovalText.defaultReviewReason
        )
        XCTAssertEqual(
            VyronProjectApprovalMode.askForApproval.commandReviewReason(for: classifiedReason),
            classifiedReason
        )
        XCTAssertNil(VyronProjectApprovalMode.approveForMe.commandReviewReason(for: nil))
        XCTAssertEqual(
            VyronProjectApprovalMode.approveForMe.commandReviewReason(for: classifiedReason),
            classifiedReason
        )
        XCTAssertNil(VyronProjectApprovalMode.fullAccess.commandReviewReason(for: nil))
        XCTAssertNil(VyronProjectApprovalMode.fullAccess.commandReviewReason(for: classifiedReason))
    }

    func testSharedApprovalResourcesResolveAllSupportedLanguages() {
        XCTAssertEqual(
            VyronProjectApprovalText.defaultReviewReason(language: .english),
            "Review this project command before it runs."
        )
        XCTAssertEqual(
            VyronProjectApprovalText.defaultReviewReason(language: .turkish),
            "Bu proje komutunu çalıştırılmadan önce inceleyin."
        )
        XCTAssertEqual(
            VyronProjectApprovalText.defaultReviewReason(language: .ukrainian),
            "Перевірте цю команду проєкту перед її виконанням."
        )
    }

    func testApprovalModesRoundTripThroughCodable() throws {
        let modes = VyronProjectApprovalMode.allCases
        let encoded = try JSONEncoder().encode(modes)
        XCTAssertEqual(try JSONDecoder().decode([VyronProjectApprovalMode].self, from: encoded), modes)
    }

    func testAskForApprovalReviewsRoutineCommandAndDeclinePreventsExecution() async throws {
        let reviews = VyronSteeringTestLog<CommandApproval>()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = try DevelopmentAgent(client: provider(["swift --version"]), workspace: workspace())
        try await agent.configureCommandApproval(.askForApproval)

        let result = try await agent.run(
            goal: "Inspect the installed Swift version.", model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: { request in
                reviews.append(request)
                return false
            }
        )

        XCTAssertEqual(reviews.values.map(\.command), ["swift --version"])
        XCTAssertEqual(reviews.values.first?.reason, VyronProjectApprovalText.defaultReviewReason)
        XCTAssertEqual(reviews.values.first?.reviewSource, .approvalSetting)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertFalse(events.values.contains { $0.kind == .commandStarted })
        XCTAssertTrue(events.values.contains { $0.failure?.contains("declined") == true })
    }

    func testDefaultPolicyRunsRoutineCommandWithoutReview() async throws {
        let result = try await DevelopmentAgent(client: provider(["swift --version"]), workspace: workspace()).run(
            goal: "Inspect the installed Swift version.", model: "fixture-coder",
            onEvent: { _ in }, approveCommand: { _ in
                XCTFail("Approve for me should keep routine development commands automatic.")
                return false
            }
        )

        XCTAssertEqual(result.commands.map(\.command), ["swift --version"])
        try requireSuccessfulProtectedCommand(XCTUnwrap(result.commands.first))
    }

    func testDefaultPolicyReviewsUnfamiliarCommandBeforeExecution() async throws {
        let reviews = VyronSteeringTestLog<CommandApproval>()
        let command = "/usr/bin/true"
        let result = try await DevelopmentAgent(client: provider([command]), workspace: workspace()).run(
            goal: "Review a local project command.", model: "fixture-coder",
            onEvent: { _ in }, approveCommand: { request in
                reviews.append(request)
                return false
            }
        )

        XCTAssertEqual(reviews.values.map(\.command), [command])
        XCTAssertEqual(reviews.values.first?.reason, DevelopmentWorkspace.approvalRequirement(command: command))
        XCTAssertTrue(result.commands.isEmpty)
    }

    func testFullAccessRunsPermittedUnfamiliarCommandOnceAndRetainsReplayProtection() async throws {
        let command = "/usr/bin/true"
        let scripted = VyronSteeringTestProvider { round, _ in
            if round <= 2 {
                return DevelopmentMessage(role: "assistant", toolCalls: [DevelopmentToolCall(
                    name: "run_command", arguments: ["command": .string(command)], id: "round-\(round)"
                )])
            }
            return DevelopmentMessage(role: "assistant", content: "The project command completed once.")
        }
        let agent = try DevelopmentAgent(client: scripted, workspace: workspace())
        try await agent.configureCommandApproval(.fullAccess)

        let result = try await agent.run(
            goal: "Run one local project command exactly once.", model: "fixture-coder",
            onEvent: { _ in }, approveCommand: { _ in
                XCTFail("Full access should not prompt for a permitted local command.")
                return false
            }
        )

        XCTAssertEqual(result.commands.map(\.command), [command])
        let requests = await scripted.recordedRequests()
        XCTAssertTrue(requests[2].contains { $0.content.contains("it was not run again") })
        try requireSuccessfulProtectedCommand(XCTUnwrap(result.commands.first))
    }

    func testFullAccessDoesNotBypassForbiddenCommandValidation() async throws {
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = try DevelopmentAgent(
            client: provider(["curl https://example.invalid", "rm Unsafe.txt", "git push"]), workspace: workspace()
        )
        try await agent.configureCommandApproval(.fullAccess)

        let result = try await agent.run(
            goal: "Inspect proposed commands without changing the execution boundary.", model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: { _ in
                XCTFail("Forbidden commands must be refused before any approval callback.")
                return true
            }
        )

        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertFalse(events.values.contains { $0.kind == .commandStarted })
        XCTAssertEqual(events.values.filter { $0.kind == .toolFinished && $0.failure != nil }.count, 3)
    }

    func testFullAccessPreservesReadOnlyPlanMode() async throws {
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = try DevelopmentAgent(client: provider(["/usr/bin/true"]), workspace: workspace())
        try await agent.configureCommandApproval(.fullAccess)

        let result = try await agent.run(
            goal: "Plan a project change without executing commands.", model: "fixture-coder", mode: .plan,
            onEvent: { events.append($0) }, approveCommand: { _ in
                XCTFail("Plan must remain read-only under full access.")
                return true
            }
        )

        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(events.values.contains { $0.failure?.contains("Plan mode is read-only") == true })
    }

    func testPolicyCannotChangeWhileRunIsAwaitingReview() async throws {
        let rejected = VyronSteeringTestLog<Bool>()
        let agent = try DevelopmentAgent(client: provider(["swift --version"]), workspace: workspace())
        try await agent.configureCommandApproval(.askForApproval)

        let result = try await agent.run(
            goal: "Inspect the installed Swift version.", model: "fixture-coder",
            onEvent: { _ in }, approveCommand: { _ in
                do {
                    try await agent.configureCommandApproval(.fullAccess)
                    rejected.append(false)
                } catch DevelopmentAgentError.alreadyRunning {
                    rejected.append(true)
                } catch {
                    XCTFail("Unexpected configuration error: \(error)")
                }
                return false
            }
        )

        XCTAssertEqual(rejected.values, [true])
        XCTAssertTrue(result.commands.isEmpty)
        try await agent.configureCommandApproval(.approveForMe)
    }

    func testCancellationWhileReviewIsPendingIgnoresLateApproval() async throws {
        let review = VyronProjectApprovalTestReview()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let agent = try DevelopmentAgent(client: provider(["swift --version"]), workspace: workspace())
        try await agent.configureCommandApproval(.askForApproval)
        let execution = Task {
            try await agent.run(
                goal: "Inspect the installed Swift version.", model: "fixture-coder",
                onEvent: { events.append($0) }, approveCommand: { await review.waitForDecision($0) }
            )
        }
        do {
            try await waitUntil { await review.requests.count == 1 }
        } catch {
            execution.cancel()
            await review.resolve(false)
            _ = await execution.result
            throw error
        }
        execution.cancel()
        let outcome = await execution.result
        await review.resolve(true)
        switch outcome {
        case .success:
            XCTFail("Cancellation must stop the pending command review.")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Unexpected cancellation error: \(error)")
        }
        XCTAssertFalse(events.values.contains { $0.kind == .commandStarted })
    }

    func testNewGuidanceDuringRoutineCommandReviewPreventsStaleExecution() async throws {
        let inbox = VyronSteeringInbox()
        let update = VyronSteeringMessage(content: "Skip the command and explain the next steps.")
        let agent = try DevelopmentAgent(client: provider(["swift --version"]), workspace: workspace())
        try await agent.configureCommandApproval(.askForApproval)

        let result = try await agent.run(
            goal: "Inspect the installed Swift version.", model: "fixture-coder", steeringInbox: inbox,
            onEvent: { _ in }, approveCommand: { _ in
                await inbox.append(update)
                return true
            }
        )

        XCTAssertTrue(result.commands.isEmpty)
    }

    private func provider(_ commands: [String]) -> VyronSteeringTestProvider {
        VyronSteeringTestProvider { round, _ in
            if round == 1 {
                return DevelopmentMessage(role: "assistant", toolCalls: commands.enumerated().map { index, command in
                    DevelopmentToolCall(
                        name: "run_command", arguments: ["command": .string(command)], id: "command-\(index)"
                    )
                })
            }
            return DevelopmentMessage(role: "assistant", content: "The command review is complete.")
        }
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronProjectApproval-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return try DevelopmentWorkspace(rootURL: directory)
    }

    private func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("The command approval operation did not reach its expected state.")
        throw CancellationError()
    }

    private func requireSuccessfulProtectedCommand(_ command: CommandResult) throws {
        let output = command.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if command.exitCode == 71, !command.timedOut,
            output == "sandbox-exec: sandbox_apply: Operation not permitted" {
            throw XCTSkip(
                "BLOCKED: macOS refused the nested execution protection required by this command: " + output
            )
        }
        XCTAssertTrue(
            command.succeeded,
            "Command \(command.command) exited \(command.exitCode); timed out: \(command.timedOut). Output: \(command.output)"
        )
    }
}
