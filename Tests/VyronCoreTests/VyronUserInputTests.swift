import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronUserInputTests: XCTestCase {
    private func workspace() throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VyronQuestions-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return try DevelopmentWorkspace(rootURL: root)
    }

    private func call(questions: [DevelopmentJSONValue]? = nil) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "request_user_input", arguments: [
            "questions": .array(questions ?? [.object([
                "id": .string("layout"), "question": .string("Which layout should I use?"),
                "options": .array([
                    .object(["label": .string("Compact"), "description": .string("Fits more content.")]),
                    .object(["label": .string("Spacious"), "description": .string("Adds breathing room.")])
                ])
            ])])
        ], id: "question-call")
    }

    func testQuestionToolIsAvailableInAgentAndReadOnlyPlan() throws {
        for mode in [DevelopmentMode.agent, .plan] {
            let definitions = try DevelopmentToolDefinition.available(mode: mode, externalTools: [])
            let question = try XCTUnwrap(definitions.first { $0.function.name == "request_user_input" })
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: JSONEncoder().encode(question)) as? [String: Any]
            )
            let function = try XCTUnwrap(object["function"] as? [String: Any])
            let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
            XCTAssertEqual(parameters["required"] as? [String], ["questions"])
            XCTAssertEqual(parameters["additionalProperties"] as? Bool, false)
            if mode == .plan {
                XCTAssertFalse(definitions.contains { ["write_file", "edit_file", "run_command"].contains($0.function.name) })
            }
        }
        XCTAssertThrowsError(try DevelopmentToolDefinition.available(mode: .agent, externalTools: [
            DevelopmentExternalTool(
                name: "request_user_input", description: "Conflicting integration",
                inputSchema: ["type": .string("object")], isReadOnly: true
            )
        ]))
    }

    func testStrictQuestionParsingAndNativeRequestIdentity() throws {
        let parsed = try VyronUserInputTool.decode(call())
        XCTAssertEqual(parsed.questions.first?.id, "layout")
        XCTAssertEqual(parsed.questions.first?.options.map(\.label), ["Compact", "Spacious"])
        XCTAssertNotEqual(parsed.id, try VyronUserInputTool.decode(call()).id)
        let freeform = try VyronUserInputTool.decode(call(questions: [
            .object(["id": .string("name"), "question": .string("What name should I use?")])
        ]))
        XCTAssertEqual(freeform.questions.first?.options, [])
        let encoded = try JSONEncoder().encode(parsed)
        XCTAssertEqual(try JSONDecoder().decode(VyronUserInputRequest.self, from: encoded), parsed)
    }

    func testMalformedQuestionsAndExtraTransportKeysAreRejected() throws {
        let valid = try XCTUnwrap(call().function.arguments["questions"])
        guard case .array(let questions) = valid else { return XCTFail("Missing questions") }
        let invalid: [[DevelopmentJSONValue]] = [
            [], Array(repeating: questions[0], count: 4), [questions[0], questions[0]],
            [.object(["id": .string("layout"), "question": .string("   ")])],
            [.object(["id": .string("layout"), "question": .string("A?"), "unknown": .bool(true)])],
            [.object(["id": .string("layout"), "question": .string("A?"), "options": .array([
                .object(["label": .string("Only"), "description": .string("One choice.")])
            ])])],
            [.object(["id": .string("layout"), "question": .string(String(repeating: "x", count: 801))])]
        ]
        for questions in invalid { XCTAssertThrowsError(try VyronUserInputTool.decode(call(questions: questions))) }
        XCTAssertThrowsError(try VyronUserInputTool.decode(DevelopmentToolCall(
            name: "request_user_input", arguments: ["questions": valid, "authorization": .bool(true)]
        )))
    }

    func testAnswersRequireExactRequestAndUniqueCompleteQuestionIDs() throws {
        let request = VyronUserInputRequest(questions: [
            VyronUserInputQuestion(id: "first", question: "First?"),
            VyronUserInputQuestion(id: "second", question: "Second?")
        ])
        let good = [
            VyronUserInputAnswer(questionID: "first", value: "Custom answer"),
            VyronUserInputAnswer(questionID: "second", value: "Second answer")
        ]
        try VyronUserInputTool.validate(.init(requestID: request.id, answers: good), for: request)
        let invalid = [
            VyronUserInputResponse(requestID: UUID(), answers: good),
            .init(requestID: request.id, answers: [good[0]]),
            .init(requestID: request.id, answers: [good[0], good[0]]),
            .init(requestID: request.id, answers: [good[0], .init(questionID: "wrong", value: "Answer")]),
            .init(requestID: request.id, answers: [good[0], .init(questionID: "second", value: " \n ")]),
            .init(requestID: request.id, answers: [good[0], .init(
                questionID: "second", value: String(repeating: "é", count: 1_001)
            )])
        ]
        for response in invalid { XCTAssertThrowsError(try VyronUserInputTool.validate(response, for: request)) }
    }

    func testAnswerContinuesSameAgentLoopAndSkipsActionsProposedBeforeChoice() async throws {
        let questionCall = call()
        let stale = DevelopmentToolCall(name: "write_file", arguments: [
            "path": .string("stale.txt"), "content": .string("Stale layout")
        ], id: "stale-write")
        for calls in [[questionCall, stale], [stale, questionCall]] {
            let provider = VyronSteeringTestProvider { round, _ in
                round == 1
                    ? DevelopmentMessage(role: "assistant", toolCalls: calls)
                    : DevelopmentMessage(role: "assistant", content: "I will use your custom layout.")
            }
            let asked = VyronSteeringTestLog<VyronUserInputRequest>()
            let agent = try DevelopmentAgent(client: provider, workspace: workspace(), requestUserInput: { request in
                asked.append(request)
                return VyronUserInputResponse(requestID: request.id, answers: [
                    VyronUserInputAnswer(questionID: "layout", value: "Use a custom middle ground.")
                ])
            })
            let result = try await agent.run(
                goal: "Design the layout", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false }
            )
            let requests = await provider.recordedRequests()
            XCTAssertEqual(asked.values.count, 1)
            XCTAssertEqual(requests.count, 2)
            XCTAssertEqual(requests[1].filter { $0.role == "tool" }.map(\.toolCallID), calls.map(\.id))
            XCTAssertTrue(requests[1].last?.content.contains("Use a custom middle ground.") == true)
            XCTAssertEqual(requests[1].last?.role, "user", "Answers survive bounded-context retention as user guidance")
            XCTAssertTrue(requests[1].first { $0.toolCallID == "stale-write" }?.content.contains("Not executed") == true)
            XCTAssertTrue(result.changedFiles.isEmpty)
            XCTAssertTrue(result.finalMessage.contains("custom layout"))
        }
    }

    func testReadOnlyPlanCanAskWithoutCommandsOrEdits() async throws {
        let questionCall = call()
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1
                ? DevelopmentMessage(role: "assistant", toolCalls: [questionCall])
                : DevelopmentMessage(role: "assistant", content: "Plan: keep the compact layout.")
        }
        let agent = try DevelopmentAgent(client: provider, workspace: workspace(), requestUserInput: { request in
            VyronUserInputResponse(requestID: request.id, answers: [.init(questionID: "layout", value: "Compact")])
        })
        let result = try await agent.run(
            goal: "Plan the layout", model: "fixture-coder", mode: .plan,
            onEvent: { _ in }, approveCommand: { _ in false }
        )
        XCTAssertEqual(result.steps, 2)
        XCTAssertTrue(result.commands.isEmpty)
        XCTAssertTrue(result.changedFiles.isEmpty)
    }

    func testMissingHandlerReturnsToolErrorWithoutInventingAnAnswer() async throws {
        let questionCall = call()
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1
                ? DevelopmentMessage(role: "assistant", toolCalls: [questionCall])
                : DevelopmentMessage(role: "assistant", content: "A layout preference is still needed.")
        }
        _ = try await DevelopmentAgent(client: provider, workspace: workspace()).run(
            goal: "Review the layout", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false }
        )
        let requests = await provider.recordedRequests()
        let response = try XCTUnwrap(requests[1].last)
        XCTAssertEqual(response.toolCallID, "question-call")
        XCTAssertTrue(response.content.contains("\"ok\":false"))
        XCTAssertTrue(response.content.contains("unavailable"))
    }

    func testMalformedQuestionNeverOpensAUserPrompt() async throws {
        let questionCall = call(questions: [])
        let provider = VyronSteeringTestProvider { round, _ in
            round == 1
                ? DevelopmentMessage(role: "assistant", toolCalls: [questionCall])
                : DevelopmentMessage(role: "assistant", content: "I need to revise my question.")
        }
        let asked = VyronSteeringTestLog<VyronUserInputRequest>()
        let agent = try DevelopmentAgent(client: provider, workspace: workspace(), requestUserInput: { request in
            asked.append(request)
            throw CancellationError()
        })
        _ = try await agent.run(
            goal: "Review the layout", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false }
        )
        XCTAssertTrue(asked.values.isEmpty)
    }

    func testCancellationWhileWaitingStopsWithoutAnotherModelRequest() async throws {
        let questionCall = call()
        let provider = VyronSteeringTestProvider { _, _ in
            DevelopmentMessage(role: "assistant", toolCalls: [questionCall])
        }
        let waiting = expectation(description: "Question handler is waiting")
        let agent = try DevelopmentAgent(client: provider, workspace: workspace(), requestUserInput: { _ in
            waiting.fulfill()
            try await Task.sleep(for: .seconds(30))
            throw CancellationError()
        })
        let execution = Task {
            try await agent.run(
                goal: "Review the layout", model: "fixture-coder", onEvent: { _ in }, approveCommand: { _ in false }
            )
        }
        let waitResult = await XCTWaiter.fulfillment(of: [waiting], timeout: 2)
        XCTAssertEqual(waitResult, .completed)
        execution.cancel()
        do {
            _ = try await execution.value
            XCTFail("Stop must cancel the pending question")
        } catch is CancellationError {
            let requests = await provider.recordedRequests()
            XCTAssertEqual(requests.count, 1)
        }
    }

    func testGatePreservesFirstResolutionBeforeContinuationInstallation() async throws {
        let response = VyronUserInputResponse(requestID: UUID(), answers: [])
        let gate = VyronUserInputGate()
        gate.resolve(.success(response))
        gate.resolve(.failure(CancellationError()))
        let result = try await withCheckedThrowingContinuation { continuation in
            XCTAssertFalse(gate.install(continuation))
        }
        XCTAssertEqual(result, response)
    }

    func testGatePreservesCancellationBeforeContinuationInstallation() async throws {
        let gate = VyronUserInputGate()
        gate.resolve(.failure(CancellationError()))
        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                XCTAssertFalse(gate.install(continuation))
            }
            XCTFail("A canceled request cannot be reopened")
        } catch is CancellationError {
            // A late worker cannot change the resolved cancellation.
            gate.resolve(.success(.init(requestID: UUID(), answers: [])))
        }
    }
}
