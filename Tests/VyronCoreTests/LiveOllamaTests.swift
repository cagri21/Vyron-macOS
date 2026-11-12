import Foundation
import XCTest
@testable import VyronCore

/// Opt in only after a local model is installed:
/// VYRON_LIVE_MODEL=qwen3-coder:30b swift test --filter LiveOllamaTests
final class LiveOllamaTests: XCTestCase, @unchecked Sendable {
    private func configuredModel() throws -> String {
        guard let model = ProcessInfo.processInfo.environment["VYRON_LIVE_MODEL"], !model.isEmpty else {
            throw XCTSkip("Set VYRON_LIVE_MODEL to run against an installed local Ollama model.")
        }
        try OllamaClient.validateModelName(model)
        return model
    }

    func testInstalledModelIsDiscoverableOnLoopback() async throws {
        let name = try configuredModel()
        let models = try await OllamaClient().models()
        let expected = name.contains(":") ? name : name + ":latest"
        XCTAssertTrue(models.contains(where: { $0.name == expected }), "Expected \(expected) among local models: \(models.map(\.name))")
        let selected = models.first(where: { $0.name == expected })
        XCTAssertGreaterThan(selected?.size ?? 0, 0)
    }

    func testActualChatStreamsAndReturnsTheSameText() async throws {
        let name = try configuredModel()
        let received = LiveTokenBuffer()
        let output = try await OllamaClient().chat(
            model: name,
            messages: [ChatMessage(role: "user", content: "Reply with exactly LOCAL_OK.")],
            systemPrompt: "Give a short answer. You are running locally on this Mac."
        ) { received.append($0) }
        XCTAssertFalse(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertGreaterThan(received.count, 0)
        XCTAssertEqual(output, received.joined)
        print("Live local model \(name): \(output.prefix(200))")
    }

    func testActualStreamingGenerationCanBeCancelledAfterFirstToken() async throws {
        let name = try configuredModel()
        let client = OllamaClient()
        let (tokens, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let generation = Task {
            defer { continuation.finish() }
            return try await client.chat(
                model: name,
                messages: [ChatMessage(role: "user", content: "Count upward from 1 to 10000, spelling out each number on its own line. Continue until all ten thousand numbers are complete.")]
            ) { _ in continuation.yield(()) }
        }
        var receivedToken = false
        for await _ in tokens {
            receivedToken = true
            generation.cancel()
            break
        }
        XCTAssertTrue(receivedToken, "The local model never produced a token before generation ended.")
        do {
            _ = try await generation.value
            XCTFail("Expected generation to stop with cancellation.")
        } catch {
            XCTAssertTrue(error is CancellationError, "Expected cancellation, received \(error)")
        }
    }

    func testActualControlPlannerReturnsAReviewableActionOnly() async throws {
        let name = try configuredModel()
        let proposal = try await OllamaClient().proposeControl(
            model: name,
            instruction: "Click the Back button, element 1.",
            snapshot: "Application: Safari\nApp ID: com.apple.Safari\n[1] Button · Back {click}\n[2] TextField · Search {set text}",
            applicationID: "com.apple.Safari"
        )
        _ = try proposal.validated(expectedApplicationID: "com.apple.Safari", availableElementIDs: [1, 2])
        XCTAssertEqual(proposal.kind, .click)
        XCTAssertEqual(proposal.elementID, 1)
        print("Live local proposal only: \(proposal.kind.rawValue) element \(proposal.elementID ?? -1). No action executed.")
    }

    func testActualTaskPlannerRecognizesVisibleCompletionWithoutAnAction() async throws {
        let name = try configuredModel()
        let proposal = try await OllamaClient().proposeControl(
            model: name,
            instruction: "Open https://example.com and verify the page title is Example Domain.",
            snapshot: "Application: Safari\nApp ID: com.apple.Safari\n[1] TextField · Address · https://example.com/ {set text}\n[2] StaticText · Example Domain\n[3] StaticText · This domain is for use in illustrative examples in documents.",
            applicationID: "com.apple.Safari",
            taskHistory: "Step 1: openURL https://example.com. Result: action sent. A new snapshot was captured afterward."
        )
        _ = try proposal.validated(expectedApplicationID: "com.apple.Safari", availableElementIDs: [1, 2, 3])
        XCTAssertEqual(proposal.kind, .complete)
        XCTAssertNil(proposal.elementID)
        XCTAssertNil(proposal.text)
        XCTAssertNil(proposal.url)
        XCTAssertNil(proposal.key)
        XCTAssertTrue(proposal.explanation.localizedCaseInsensitiveContains("Example Domain"))
        print("Live local completion report only: \(proposal.explanation). No action executed.")
    }

    func testActualAgentChoosesTheRelevantApplicationBeforeUsingItsControls() async throws {
        let name = try configuredModel()
        let decision = try await OllamaClient().planAgent(
            model: name,
            goal: "Click the Back button in Safari. Inspect its current controls first.",
            applications: [AgentApplication(id: "com.apple.TextEdit", name: "TextEdit"), AgentApplication(id: "com.apple.Safari", name: "Safari")],
            snapshot: nil,
            history: "No tool steps have run yet."
        )
        XCTAssertEqual(decision.proposal.applicationID, "com.apple.Safari")
        XCTAssertEqual(decision.proposal.kind, .inspect)
        let availableModels = try await OllamaClient().models()
        let routedModel = AgentModelRouter.selectModel(from: availableModels, preferredModel: name, effort: decision.effort)
        XCTAssertEqual(decision.model, routedModel?.name)
        XCTAssertNotEqual(decision.effort, .automatic)
        print("Live local agent chose \(decision.proposal.kind.rawValue) in \(decision.proposal.applicationID ?? "unknown") with \(decision.effort.rawValue) effort. No action executed.")
    }

    func testActualIntentRouterDistinguishesAQuestionFromAMacRequest() async throws {
        let name = try configuredModel()
        let client = OllamaClient()
        let question = try await client.routeRequest(text: "What is 2+2?", preferredModel: name)
        XCTAssertEqual(question.mode, .conversation)
        XCTAssertNil(question.goal)
        let task = try await client.routeRequest(text: "Open Calculator", preferredModel: name)
        XCTAssertEqual(task.mode, .computerTask)
        XCTAssertEqual(task.goal, "Open Calculator")
        print("Live local routing distinguished conversation from a computer task. No app inspection or action executed.")
    }
}

private final class LiveTokenBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [String] = []
    func append(_ token: String) { lock.withLock { tokens.append(token) } }
    var count: Int { lock.withLock { tokens.count } }
    var joined: String { lock.withLock { tokens.joined() } }
}
