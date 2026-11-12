import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore
@testable import VyronModelData

private final class ActivityStubRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nextPort = 29_000
    private var stubs: [Int: ActivityNetworkStub] = [:]

    func register(_ stub: ActivityNetworkStub) -> Int {
        lock.withLock {
            nextPort += 1
            stubs[nextPort] = stub
            return nextPort
        }
    }

    func stub(for port: Int) -> ActivityNetworkStub? {
        lock.withLock { stubs[port] }
    }

    func remove(_ port: Int) {
        _ = lock.withLock { stubs.removeValue(forKey: port) }
    }
}

private final class ActivityStubURLProtocol: URLProtocol, @unchecked Sendable {
    static let registry = ActivityStubRegistry()
    private let lock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let port = request.url?.port, let stub = Self.registry.stub(for: port) else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        stub.handle(self)
    }

    override func stopLoading() {
        lock.withLock { stopped = true }
    }

    func respond(status: Int = 200, body: String) {
        guard !lock.withLock({ stopped }) else { return }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/x-ndjson"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private final class ActivityNetworkStub: @unchecked Sendable {
    enum Reply: Sendable {
        case success(String), failure, held, agent, agentToolFailure
    }

    private let lock = NSLock()
    private let reply: Reply
    private var chats: [ActivityStubURLProtocol] = []

    init(reply: Reply) { self.reply = reply }

    var chatRequestCount: Int { lock.withLock { chats.count } }

    func handle(_ request: ActivityStubURLProtocol) {
        switch request.request.url?.path {
        case "/api/tags":
            request.respond(body: #"{"models":[{"name":"qwen3-coder:30b","size":1,"capabilities":["completion","tools"]}]}"#)
        case "/api/chat":
            // Optional hints are a separate request after the answer is complete. Keep
            // these tests' step counts and held requests focused on response activity.
            if Self.isSuggestionRequest(request.request) {
                request.respond(body: Self.stream(#"{"questions":[]}"#))
                return
            }
            let step = lock.withLock { chats.append(request); return chats.count }
            switch reply {
            case .success(let text): request.respond(body: Self.stream(text))
            case .failure: request.respond(status: 500, body: #"{"error":"Test model failure"}"#)
            case .held: break
            case .agent:
                if step == 1 {
                    request.respond(body: #"{"message":{"role":"assistant","content":"I will read the project notes before explaining the project.","tool_calls":[{"function":{"name":"read_file","arguments":{"path":"README.md"}}}]},"done":true}"#)
                } else {
                    request.respond(body: #"{"message":{"role":"assistant","content":"The project notes describe a small Swift application."},"done":true}"#)
                }
            case .agentToolFailure:
                if step == 1 {
                    request.respond(body: #"{"message":{"role":"assistant","content":"I will check the available project notes.","tool_calls":[{"function":{"name":"read_file","arguments":{"path":"README.md"}}},{"function":{"name":"read_file","arguments":{"path":"Missing.md"}}}]},"done":true}"#)
                } else {
                    request.respond(body: #"{"message":{"role":"assistant","content":"The optional notes file is unavailable. The existing project notes were read."},"done":true}"#)
                }
            }
        default:
            request.respond(status: 404, body: #"{"error":"Unexpected test endpoint"}"#)
        }
    }

    func completeChat(at index: Int, text: String) {
        let request = lock.withLock { chats[index] }
        request.respond(body: Self.stream(text))
    }

    private static func stream(_ text: String) -> String {
        let chunk = try! JSONSerialization.data(withJSONObject: ["message": ["content": text], "done": false])
        return String(decoding: chunk, as: UTF8.self) + "\n{\"done\":true}\n"
    }

    private static func isSuggestionRequest(_ request: URLRequest) -> Bool {
        let data: Data
        if let body = request.httpBody {
            data = body
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
            data = body
        } else {
            return false
        }
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = payload["messages"] as? [[String: Any]] else { return false }
        return messages.contains {
            $0["role"] as? String == "system" && ($0["content"] as? String)?.hasPrefix("Generate suggested follow-up questions") == true
        }
    }
}

@MainActor
final class AppModelActivityTests: XCTestCase {
    private enum TestError: Error { case timedOut }

    @MainActor
    private struct Harness {
        let directory: URL
        let stub: ActivityNetworkStub
        let port: Int
        let client: OllamaClient
        let model: AppModel
        let savedDefaults: [VyronUserDefaultsKey: Any]
        static let defaultsKeys: [VyronUserDefaultsKey] = [
            .selectedLocalModel, .automaticModelSelection, .workspacePath, .recentWorkspacePaths
        ]

        func cleanUp() {
            model.stopGeneration()
            ActivityStubURLProtocol.registry.remove(port)
            try? FileManager.default.removeItem(at: directory)
            for key in Self.defaultsKeys {
                if let value = savedDefaults[key] { UserDefaults.standard.set(value, forKey: key.rawValue) }
                else { UserDefaults.standard.removeObject(forKey: key.rawValue) }
            }
        }

        func persistedConversations() throws -> [Conversation] {
            try JSONDecoder().decode(
                [Conversation].self,
                from: Data(contentsOf: directory.appendingPathComponent("conversations.json"))
            )
        }
    }

    private func harness(reply: ActivityNetworkStub.Reply = .held) throws -> Harness {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("VyronActivityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stub = ActivityNetworkStub(reply: reply)
        let port = ActivityStubURLProtocol.registry.register(stub)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ActivityStubURLProtocol.self]
        let client = OllamaClient(baseURL: URL(string: "http://127.0.0.1:\(port)")!, configuration: configuration)
        var savedDefaults: [VyronUserDefaultsKey: Any] = [:]
        for key in Harness.defaultsKeys {
            savedDefaults[key] = UserDefaults.standard.object(forKey: key.rawValue)
        }
        let model = AppModel(historyDirectory: directory, client: client)
        model.workspaceState.workspaceURL = nil
        model.composer.mode = .chat
        model.modelSelection.models = [LocalModel(name: "qwen3-coder:30b", size: 1)]
        model.modelSelection.selectedModel = "qwen3-coder:30b"
        model.modelSelection.automaticModelSelection = false
        model.modelSelection.isConnected = true
        return Harness(directory: directory, stub: stub, port: port, client: client, model: model, savedDefaults: savedDefaults)
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor () -> Bool
    ) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The local test request did not reach its expected state", file: file, line: line)
        throw TestError.timedOut
    }

    func testCompletedChatPersistsActivityAndAnswerAcrossReopen() async throws {
        let test = try harness(reply: .success("A visible answer"))
        defer { test.cleanUp() }
        test.model.composer.draft = "Explain this feature"
        test.model.send()
        XCTAssertTrue(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(test.model.messages.last?.activity?.state, .working)
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        let answer = try XCTUnwrap(test.model.messages.last)
        XCTAssertEqual(answer.content, "A visible answer")
        XCTAssertEqual(answer.activity?.state, .completed)
        XCTAssertEqual(answer.activity?.entries.last?.title, "Response ready")
        XCTAssertTrue(answer.activity?.entries.contains(where: { $0.title == "Requesting a response" }) == true)
        XCTAssertTrue(answer.activity?.entries.contains(where: { $0.title == "Writing the response" }) == true)
        XCTAssertNotNil(answer.activity?.finishedAt)
        XCTAssertEqual(try test.persistedConversations().first?.messages.last, answer)

        let reopened = AppModel(historyDirectory: test.directory, client: test.client)
        XCTAssertEqual(reopened.conversations.first?.messages.last, answer)
        XCTAssertFalse(reopened.foregroundRun.isGenerating)
    }

    func testStopBeforeFirstTokenRetainsEmptyAssistantAndStoppedActivity() async throws {
        let test = try harness()
        defer { test.cleanUp() }
        test.model.composer.draft = "Take your time"
        test.model.send()
        try await waitUntil { test.stub.chatRequestCount == 1 }
        test.model.stopGeneration()

        let answer = try XCTUnwrap(test.model.messages.last)
        XCTAssertEqual(answer.role, "assistant")
        XCTAssertEqual(answer.content, "")
        XCTAssertEqual(answer.activity?.state, .stopped)
        XCTAssertEqual(answer.activity?.entries.last?.title, "Stopped by you")
        XCTAssertFalse(test.model.foregroundRun.isGenerating)
        XCTAssertEqual(try test.persistedConversations().first?.messages.last, answer)
    }

    func testFailedRequestPreservesFailedActivityInHistory() async throws {
        let test = try harness(reply: .failure)
        defer { test.cleanUp() }
        test.model.composer.draft = "Trigger a failed request"
        test.model.send()
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        let answer = try XCTUnwrap(test.model.messages.last)
        XCTAssertEqual(answer.content, "")
        XCTAssertEqual(answer.activity?.state, .failed)
        XCTAssertEqual(answer.activity?.entries.last?.title, "Response failed")
        XCTAssertTrue(answer.activity?.entries.last?.detail?.contains("Test model failure") == true)
        XCTAssertNotNil(test.model.errorMessage)
        XCTAssertEqual(try test.persistedConversations().first?.messages.last, answer)
    }

    func testAgentPersistsPublicExplanationAndToolActivityBeforeCompletion() async throws {
        let test = try harness(reply: .agent)
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("A small Swift application.\n".utf8).write(to: project.appendingPathComponent("README.md"))
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .agent
        test.model.composer.draft = "Read the project notes and explain the project"
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        let answer = try XCTUnwrap(test.model.messages.last)
        let activity = try XCTUnwrap(answer.activity)
        XCTAssertEqual(activity.state, .completed)
        XCTAssertEqual(test.stub.chatRequestCount, 2)
        XCTAssertTrue(answer.content.contains("small Swift application"))
        let explanation = try XCTUnwrap(activity.entries.firstIndex(where: {
            $0.kind == .explanation && $0.detail == "I will read the project notes before explaining the project."
        }))
        let read = try XCTUnwrap(activity.entries.firstIndex(where: {
            $0.kind == .tool && $0.title == "Reading README.md"
        }))
        XCTAssertLessThan(explanation, read)
        XCTAssertLessThan(read, activity.entries.count - 1)
        XCTAssertEqual(activity.entries.last?.title, "Response ready")
        XCTAssertEqual(try test.persistedConversations().first?.messages.last, answer)
    }

    func testAgentKeepsToolFailureVisibleWithoutSavingFileOutputInActivity() async throws {
        let test = try harness(reply: .agentToolFailure)
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fileOutput = "FILE_OUTPUT_MUST_STAY_OUT_OF_ACTIVITY"
        try Data(fileOutput.utf8).write(to: project.appendingPathComponent("README.md"))
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .agent
        test.model.composer.draft = "Read the available project notes and report any missing notes"
        XCTAssertTrue(test.model.canSend)
        test.model.send()
        try await waitUntil { !test.model.foregroundRun.isGenerating }

        let answer = try XCTUnwrap(test.model.messages.last)
        let activity = try XCTUnwrap(answer.activity)
        let failure = try XCTUnwrap(activity.entries.first(where: { $0.title == "Tool could not complete" }))
        XCTAssertEqual(failure.kind, .tool)
        XCTAssertEqual(failure.detail, "The file does not exist: Missing.md")
        XCTAssertEqual(activity.state, .completed)
        XCTAssertEqual(activity.entries.last?.title, "Response ready")
        XCTAssertTrue(answer.content.contains("optional notes file is unavailable"))
        let activityText = activity.entries.map { $0.title + "\n" + ($0.detail ?? "") }.joined(separator: "\n")
        XCTAssertFalse(activityText.contains(fileOutput))
        XCTAssertFalse(activityText.contains("Do not bypass a refused tool"))
        XCTAssertEqual(test.stub.chatRequestCount, 2)
        XCTAssertEqual(try test.persistedConversations().first?.messages.last, answer)
    }

    func testNewConversationKeepsOldReplyRunningAndSavesBothAnswers() async throws {
        let test = try harness()
        defer {
            for id in test.model.conversations.map(\.id) where test.model.isSidebarConversationActive(id) {
                test.model.selectConversation(id)
                test.model.stopGeneration()
            }
            test.cleanUp()
        }
        test.model.computerWork.automaticRequestRouting = false
        test.model.composer.draft = "First request"
        test.model.send()
        try await waitUntil { test.stub.chatRequestCount == 1 }
        let firstID = try XCTUnwrap(test.model.selectedConversationID)
        let firstResponseID = try XCTUnwrap(test.model.messages.last?.id)

        test.model.newConversation()
        XCTAssertNil(test.model.selectedConversationID)
        XCTAssertTrue(test.model.isSidebarConversationActive(firstID))
        test.model.selectComposerMode(.chat)
        test.model.composer.draft = "Second request"
        test.model.send()
        try await waitUntil { test.stub.chatRequestCount == 2 }
        let secondID = try XCTUnwrap(test.model.selectedConversationID)
        XCTAssertNotEqual(firstID, secondID)

        test.model.selectConversation(firstID)
        XCTAssertEqual(test.model.messages.last?.id, firstResponseID)
        XCTAssertTrue(test.model.isResponseActivityLive(messageID: firstResponseID))
        test.model.selectConversation(secondID)

        test.stub.completeChat(at: 0, text: "First answer")
        try await waitUntil { !test.model.isSidebarConversationActive(firstID) }
        XCTAssertEqual(test.model.selectedConversationID, secondID)
        XCTAssertTrue(test.model.isSidebarConversationActive(secondID))
        XCTAssertEqual(test.model.messages.last?.activity?.state, .working)
        test.stub.completeChat(at: 1, text: "Second answer")
        try await waitUntil { !test.model.isSidebarConversationActive(secondID) }

        let persisted = try test.persistedConversations()
        let first = try XCTUnwrap(persisted.first(where: { $0.id == firstID })?.messages.last)
        let second = try XCTUnwrap(persisted.first(where: { $0.id == secondID })?.messages.last)
        XCTAssertEqual(first.id, firstResponseID)
        XCTAssertEqual(first.content, "First answer")
        XCTAssertEqual(first.activity?.state, .completed)
        XCTAssertEqual(second.content, "Second answer")
        XCTAssertEqual(second.activity?.state, .completed)
    }

    func testReopenMarksInterruptedActivityStoppedAndSavesRecovery() throws {
        let test = try harness()
        defer { test.cleanUp() }
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var activity = ResponseActivity(startedAt: start)
        activity.record("Reading project files", at: start.addingTimeInterval(4))
        var conversation = Conversation(title: "Interrupted chat", workspacePath: nil)
        conversation.messages = [ChatMessage(role: "assistant", content: "Partial answer", activity: activity)]
        let data = try JSONEncoder().encode([conversation])
        try data.write(to: test.directory.appendingPathComponent("conversations.json"))

        let reopened = AppModel(historyDirectory: test.directory, client: test.client)
        let answer = try XCTUnwrap(reopened.conversations.first?.messages.last)
        XCTAssertEqual(answer.content, "Partial answer")
        XCTAssertEqual(answer.activity?.state, .stopped)
        XCTAssertEqual(answer.activity?.entries.last?.title, "Interrupted when Vyron closed")
        XCTAssertEqual(answer.activity?.elapsed(), 4)
        XCTAssertFalse(reopened.foregroundRun.isGenerating)
        XCTAssertEqual(try test.persistedConversations().first?.messages.last, answer)
    }
}
