import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

final class VyronDevelopmentStagnationSummaryTests: XCTestCase, @unchecked Sendable {
    private static let evidence = "Career portfolio: native iOS applications and interview preparation."
    private static let findings = "This folder contains a mobile engineering career portfolio and interview notes."
    private static let pause = "Work paused because repeated actions made no new progress after recovery."

    func testRecoveryGuidanceChangesListingIntoContentReadingAndAnAnswer() async throws {
        let project = try workspace()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = VyronStagnationTestProvider { round, _ in
            switch round {
            case 1, 2:
                return Self.listing(round)
            case 3:
                return Self.reading(round)
            default:
                return DevelopmentMessage(role: "assistant", content: Self.findings)
            }
        } summary: { _, _ in
            XCTFail("A productive recovery should complete through the normal development reply")
            return "Unexpected summary"
        }

        let result = try await run(provider, workspace: project, events: events)
        let requests = await provider.recordedRequests()
        let summaries = await provider.recordedSummaries()
        XCTAssertEqual(requests.count, 4)
        guard requests.count >= 4 else { return }
        let guidance = requests[2].filter { $0.role == "system" }.map(\.content).joined(separator: "\n").lowercased()
        XCTAssertTrue(guidance.contains("read"), guidance)
        XCTAssertTrue(guidance.contains("representative") || guidance.contains("content"), guidance)
        XCTAssertTrue(guidance.contains("answer") || guidance.contains("findings"), guidance)
        XCTAssertTrue(requests[3].contains { $0.role == "tool" && $0.content.contains(Self.evidence) })
        XCTAssertTrue(result.isComplete, result.finalMessage)
        XCTAssertTrue(result.finalMessage.contains(Self.findings), result.finalMessage)
        XCTAssertTrue(summaries.isEmpty)
        XCTAssertEqual(events.values.filter { $0.kind == .toolStarted && $0.tool == "read_file" }.count, 1)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.changedFiles.isEmpty)
    }

    func testExhaustedStagnationSummarizesCollectedEvidenceOnceWithoutMoreTools() async throws {
        let project = try workspace()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = repeatingProvider { messages, _ in
            XCTAssertTrue(
                messages.contains { $0.content.contains(Self.evidence) }, "Summary must retain actual file content"
            )
            return Self.findings
        }

        let result = try await run(provider, workspace: project, events: events)
        let requests = await provider.recordedRequests()
        let summaries = await provider.recordedSummaries()
        XCTAssertEqual(requests.count, 1 + VyronDevelopmentRunLimits.stagnantRounds)
        XCTAssertEqual(summaries.count, 1, "The safeguard permits one text-only conclusion, never another action cycle")
        XCTAssertEqual(result.steps, requests.count)
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.finalMessage.contains(Self.findings), result.finalMessage)
        XCTAssertTrue(result.finalMessage.contains(Self.pause), result.finalMessage)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.changedFiles.isEmpty)
        XCTAssertEqual(events.values.filter { $0.kind == .toolStarted }.count, requests.count)
        XCTAssertFalse(events.values.contains { $0.kind == .commandStarted || $0.kind == .fileChanged })
        XCTAssertEqual(try String(contentsOf: project.rootURL.appendingPathComponent("Projects.md"), encoding: .utf8),
            Self.evidence)
    }

    func testUnavailableEmptyAndPrintedToolSummariesKeepTheHonestPause() async throws {
        let printedTool = "<tool_call>{\"name\":\"write_file\",\"arguments\":{\"path\":\"Unexpected.md\"}}</tool_call>"
        for mode in 0..<3 {
            let project = try workspace()
            let provider = repeatingProvider { _, _ in
                switch mode {
                case 0: throw ModelProviderError.unsupportedTools
                case 1: return " \n\t"
                default: return printedTool
                }
            }

            let result = try await run(provider, workspace: project)
            let requests = await provider.recordedRequests()
            let summaries = await provider.recordedSummaries()
            XCTAssertEqual(requests.count, 1 + VyronDevelopmentRunLimits.stagnantRounds)
            XCTAssertEqual(summaries.count, 1)
            XCTAssertFalse(result.isComplete)
            XCTAssertTrue(result.finalMessage.contains(Self.pause), result.finalMessage)
            XCTAssertFalse(result.finalMessage.contains("<tool_call>"), result.finalMessage)
            XCTAssertTrue(result.commands.isEmpty)
            XCTAssertTrue(result.changedFiles.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: project.rootURL.appendingPathComponent("Unexpected.md").path
            ))
        }
    }

    func testCancellationDuringSummaryPropagatesWithoutPublishingReturnedText() async throws {
        let project = try workspace()
        let events = VyronSteeringTestLog<DevelopmentEvent>()
        let provider = repeatingProvider { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return "This obsolete summary must never be published"
        }
        let agent = DevelopmentAgent(client: provider, workspace: project)
        let execution = Task {
            try await agent.run(
                goal: "Analyze this folder", model: "fixture-coder",
                onEvent: { events.append($0) }, approveCommand: { _ in false }
            )
        }

        do {
            _ = try await execution.value
            XCTFail("Cancelling a terminal summary must propagate cancellation")
        } catch is CancellationError {
            let requests = await provider.recordedRequests()
            let summaries = await provider.recordedSummaries()
            XCTAssertEqual(requests.count, 1 + VyronDevelopmentRunLimits.stagnantRounds)
            XCTAssertEqual(summaries.count, 1)
            XCTAssertFalse(events.values.contains {
                $0.message.contains("obsolete summary") || ($0.content?.contains("obsolete summary") == true)
            })
        }
    }

    func testTerminalSummaryClosesInboxAndRefusesLateGuidanceWithoutAcknowledgingIt() async throws {
        let project = try workspace()
        let inbox = VyronSteeringInbox()
        let late = VyronSteeringMessage(content: "Analyze certificates instead of the portfolio.")
        let acceptance = VyronSteeringTestLog<Bool>()
        let applied = VyronSteeringTestLog<VyronSteeringMessage>()
        let provider = repeatingProvider { _, _ in
            acceptance.append(await inbox.append(late))
            return Self.findings
        }

        let result = try await DevelopmentAgent(client: provider, workspace: project).run(
            goal: "Analyze this folder", model: "fixture-coder", steeringInbox: inbox,
            onSteeringApplied: { applied.append($0) }, onEvent: { _ in }, approveCommand: { _ in false }
        )

        XCTAssertEqual(acceptance.values, [false], "Late guidance must remain with the caller for its next turn")
        XCTAssertTrue(applied.values.isEmpty, "Rejected updates must never be acknowledged as handled")
        XCTAssertFalse(result.isComplete)
        XCTAssertTrue(result.finalMessage.contains(Self.findings))
        let summaries = await provider.recordedSummaries()
        XCTAssertEqual(summaries.count, 1)
    }

    private func repeatingProvider(
        summary: @escaping @Sendable ([ChatMessage], String?) async throws -> String
    ) -> VyronStagnationTestProvider {
        VyronStagnationTestProvider(step: { round, _ in Self.reading(round) }, summary: summary)
    }

    private func run(
        _ provider: VyronStagnationTestProvider,
        workspace: DevelopmentWorkspace,
        events: VyronSteeringTestLog<DevelopmentEvent> = VyronSteeringTestLog()
    ) async throws -> DevelopmentResult {
        try await DevelopmentAgent(client: provider, workspace: workspace).run(
            goal: "Analyze this folder", model: "fixture-coder",
            onEvent: { events.append($0) }, approveCommand: { _ in false }
        )
    }

    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronStagnation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        try Self.evidence.write(to: root.appendingPathComponent("Projects.md"), atomically: true, encoding: .utf8)
        return try DevelopmentWorkspace(rootURL: root)
    }

    private static func listing(_ round: Int) -> DevelopmentMessage {
        DevelopmentMessage(role: "assistant", toolCalls: [
            DevelopmentToolCall(name: "list_files", arguments: [:], id: "listing-\(round)")
        ])
    }

    private static func reading(_ round: Int) -> DevelopmentMessage {
        DevelopmentMessage(role: "assistant", toolCalls: [
            DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Projects.md")], id: "reading-\(round)")
        ])
    }
}
