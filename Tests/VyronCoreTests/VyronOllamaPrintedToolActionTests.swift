import Foundation
import XCTest
import VyronModelDomain
@testable import VyronModelData

@MainActor
final class VyronOllamaPrintedToolActionTests: XCTestCase {
    override func tearDown() {
        VyronOllamaDevelopmentRepairURLProtocol.state.reset()
        super.tearDown()
    }

    func testAnnouncedFencedToolJSONIsDetectedAcrossSupportedFenceStyles() {
        let object = #"{"tool":"run_command","command":"npx --yes wrangler login","timeout_seconds":900}"#
        for fence in ["```", "~~~", "````"] {
            let content = "**Action Summary:** Executing the Wrangler login command.\n\n"
                + fence + "json\n" + object + "\n" + fence
            XCTAssertTrue(VyronOllamaPrintedToolAction.detects(content, toolNames: ["run_command"]))
        }
        let nested = "I'm calling a native tool now:\n```JSON\n"
            + #"{"function":{"name":"run_command","arguments":{"command":"swift --version"}}}"# + "\n```"
        XCTAssertTrue(VyronOllamaPrintedToolAction.detects(nested, toolNames: ["run_command"]))
    }

    func testTutorialsExamplesAndUnannouncedJSONRemainOrdinaryText() {
        let block = "```json\n" + #"{"tool":"run_command","command":"swift --version"}"# + "\n```"
        let samples = [
            "Here is a tutorial example:\nAction Summary: Executing the command.\n" + block,
            "Example:\n\nAction Summary: Executing the command.\n" + block,
            "This hypothetical client would emit:\n" + block,
            "No command was executed. Here is the request for reference:\n" + block,
            "The documented tool payload is:\n" + block,
            block,
            "Action Summary: Executing a command.\n```python\nprint('run_command')\n```",
            "Action Summary: Executing a command.\n" + #"{"tool":"run_command","command":"swift --version"}"#,
            "Running a sample request:\n" + block
        ]
        for content in samples {
            XCTAssertFalse(VyronOllamaPrintedToolAction.detects(content, toolNames: ["run_command"]), content)
        }
    }

    func testUnknownToolNamesAndQuotedJSONStringsAreNotClassifiedAsNativeActions() {
        let unknown = "Action Summary: Executing the request.\n```json\n"
            + #"{"tool":"another_tool","command":"swift --version"}"# + "\n```"
        XCTAssertFalse(VyronOllamaPrintedToolAction.detects(unknown, toolNames: ["run_command"]))
        let quoted = "Action Summary: Running the fixture.\n```json\n"
            + #"{"message":"{\"tool\":\"run_command\"}"}"# + "\n```"
        XCTAssertFalse(VyronOllamaPrintedToolAction.detects(quoted, toolNames: ["run_command"]))
    }

    func testPrintedActionRepairsOnceAndAcceptsOnlyTheAPINativeCall() async throws {
        let printed = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: printedAction)
        )
        let call = DevelopmentToolCall(
            name: "run_command", arguments: ["command": .string("swift --version")], id: "actual-native-call"
        )
        let native = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", toolCalls: [call])
        )
        let state = VyronOllamaDevelopmentRepairURLProtocol.state
        state.configure { attempt, _ in attempt == 1 ? printed : native }

        let step = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
            model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
        )

        XCTAssertEqual(step.message.toolCalls, [call])
        XCTAssertEqual(state.requests.count, 2)
        let retry = try VyronOllamaDevelopmentRepairFixture.messages(in: XCTUnwrap(state.requests.last))
        XCTAssertEqual(retry[1].content, baseMessages[1].content)
        XCTAssertTrue(retry.last?.content.contains("No actual tool call was executed") == true)
        XCTAssertTrue(retry.last?.content.contains("no printed text will be parsed into actions") == true)
        XCTAssertFalse(retry.contains { $0.content.contains("npx --yes wrangler login") })
        XCTAssertTrue(retry.allSatisfy { $0.toolCalls == nil }, "Printed JSON must never become a native call.")
    }

    func testRepeatedPrintedActionFailsAfterOneRepairInsteadOfCompleting() async throws {
        let printed = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: printedAction)
        )
        let state = VyronOllamaDevelopmentRepairURLProtocol.state
        state.configure { _, _ in printed }

        do {
            _ = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
                model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
            )
            XCTFail("An announced action without a native tool call must not complete the task.")
        } catch DevelopmentAgentError.invalidTool(let detail) {
            XCTAssertTrue(detail.contains("No printed command was executed"))
        }
        XCTAssertEqual(state.requests.count, 2)
    }

    func testLegitimateFencedTutorialReturnsUnchangedWithoutRepair() async throws {
        let example = "Tutorial example, no command is executed:\n" + printedAction
        let reply = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: example)
        )
        let state = VyronOllamaDevelopmentRepairURLProtocol.state
        state.configure { _, _ in reply }

        let step = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
            model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
        )

        XCTAssertEqual(step.message.content, example)
        XCTAssertTrue(step.message.toolCalls?.isEmpty ?? true)
        XCTAssertEqual(state.requests.count, 1)
    }

    func testRealNativeCallsRemainValidEvenWhenContentContainsAnAnnouncement() async throws {
        let call = DevelopmentToolCall(name: "list_files", arguments: [:], id: "native-list")
        let reply = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: printedAction, toolCalls: [call])
        )
        let state = VyronOllamaDevelopmentRepairURLProtocol.state
        state.configure { _, _ in reply }

        let step = try await VyronOllamaDevelopmentRepairFixture.client().developmentStep(
            model: VyronOllamaDevelopmentRepairFixture.model, messages: baseMessages
        )

        XCTAssertEqual(step.message.toolCalls, [call])
        XCTAssertEqual(state.requests.count, 1)
    }

    func testCancellationStopsBeforePrintedActionRepair() async throws {
        let printed = try VyronOllamaDevelopmentRepairFixture.reply(
            DevelopmentMessage(role: "assistant", content: printedAction)
        )
        let client = try VyronOllamaDevelopmentRepairFixture.client()
        let messages = baseMessages
        let operation = Task {
            try await client.developmentStep(model: VyronOllamaDevelopmentRepairFixture.model, messages: messages)
        }
        let state = VyronOllamaDevelopmentRepairURLProtocol.state
        state.configure { _, _ in
            operation.cancel()
            return printed
        }

        switch await operation.result {
        case .success:
            XCTFail("Cancellation must stop before the repair request.")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "Unexpected failure: \(error)")
        }
        XCTAssertEqual(state.requests.count, 1)
    }

    private var printedAction: String {
        "Action Summary: Executing the Wrangler login command.\n```json\n"
            + #"{"tool":"run_command","command":"npx --yes wrangler login","timeout_seconds":900}"# + "\n```"
    }

    private var baseMessages: [DevelopmentMessage] {
        [
            DevelopmentMessage(role: "system", content: "Keep the existing task and command access restrictions."),
            DevelopmentMessage(role: "user", content: "Inspect the project with native tools.")
        ]
    }
}
