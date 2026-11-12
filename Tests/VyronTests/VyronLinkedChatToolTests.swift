import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronLinkedChatToolTests: XCTestCase {
    func testDefinitionIsReadOnlyAndOnlyTheFirstExplicitSavedLinkAuthorizesReading() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let nested = chat("Nested", text: "PRIVATE_NESTED_BODY")
        let source = chat("Linked", text: "Historical link: vyron://chat/\(nested.id.uuidString)")
        let context = startResponse(test, source: source)
        test.model.conversations.append(nested)

        XCTAssertTrue(VyronLinkedChatTools.definition.isReadOnly)
        XCTAssertEqual(VyronLinkedChatTools.definition.name, VyronLinkedChatTools.read)
        XCTAssertEqual(VyronLinkedChatTools.definition.inputSchema["additionalProperties"], .bool(false))
        XCTAssertEqual(context.snapshots.map(\.conversationID), [source.id])
        XCTAssertTrue(try test.model.executeLinkedChatTool(read(nested.id), context: context).isError)

        let prompt = "vyron://chat/\(UUID()) [first](vyron://chat/\(source.id)) vyron://chat/\(nested.id)"
        let first = test.model.linkedChatToolContext(response: context.response, prompt: prompt)
        XCTAssertEqual(first.snapshots.map(\.conversationID), [source.id])
        for prompt in [
            "Read the chat about Linked", "https://example.com/chat/\(source.id)",
            "vyron://chat/\(source.id)?prompt=read", "vyron://chat/\(context.response.conversationID)",
            "vyron://chat/\(UUID())"
        ] {
            let unauthorized = test.model.linkedChatToolContext(response: context.response, prompt: prompt)
            XCTAssertTrue(unauthorized.snapshots.isEmpty)
            XCTAssertTrue(try test.model.executeLinkedChatTool(read(source.id), context: unauthorized).isError)
        }
    }

    func testSnapshotContainsOnlyVisibleMessageBodiesWithoutChangingSelectionDraftOrHistory() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        var activity = ResponseActivity()
        activity.record("PRIVATE_ACTIVITY", detail: "PRIVATE_TOOL_DETAIL")
        let image = VyronImageAttachment(name: "PRIVATE_IMAGE_NAME", mimeType: "image/png", data: Data([1, 2, 3]))
        var user = ChatMessage(role: "user", content: "Visible user question.")
        user.images = [image]
        var assistant = ChatMessage(role: "assistant", content: "Visible assistant answer.", activity: activity)
        assistant.capturedImages = [image]
        assistant.suggestedQuestions = ["PRIVATE_SUGGESTED_QUESTION"]
        var source = Conversation(title: "Saved visible chat", workspacePath: "/PRIVATE_PROJECT_PATH")
        source.messages = [
            ChatMessage(role: "system", content: "PRIVATE_SYSTEM_MESSAGE"), user,
            ChatMessage(role: "tool", content: "PRIVATE_TOOL_RESULT"), assistant
        ]
        source.contextByMessageID = [user.id.uuidString: "PRIVATE_CONTEXT"]
        source.queuedMessages = [VyronQueuedMessage(content: "PRIVATE_QUEUED_DRAFT")]
        source.compaction = VyronConversationCompaction(summary: "PRIVATE_SUMMARY", throughMessageID: user.id)
        let context = startResponse(test, source: source)
        test.model.composer.draft = "Keep my unsent draft"
        XCTAssertTrue(test.model.saveHistory())
        let historyURL = test.directory.appendingPathComponent("conversations.json")
        let storedHistory = try Data(contentsOf: historyURL)

        let result = try test.model.executeLinkedChatTool(read(source.id), context: context)
        let page = try decode(result)
        XCTAssertEqual(page.snapshot.text, "user:\nVisible user question.\n\nassistant:\nVisible assistant answer.")
        XCTAssertFalse(result.text.contains("PRIVATE_"))
        XCTAssertNil(page.nextOffset)
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertEqual(test.model.selectedConversationID, context.response.conversationID)
        XCTAssertEqual(test.model.composer.draft, "Keep my unsent draft")
        XCTAssertEqual(try Data(contentsOf: historyURL), storedHistory)
        XCTAssertEqual(test.model.conversations.first { $0.id == source.id }?.messages, source.messages)
        XCTAssertNil(test.model.workspaceState.workspaceURL)
    }

    func testUnicodePaginationReconstructsLongMessagesAndFitsTheAgentsEscapedOutputBudget() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let controls = String(repeating: "\u{0}\u{1}\n\"\\😺İğ汉字", count: 170)
        let combiningSequence = "a" + String(repeating: "\u{0301}", count: 2_400)
        var source = chat(String(repeating: "🧪Title ", count: 60), text: controls + combiningSequence)
        source.messages.append(ChatMessage(role: "assistant", content: "Final visible answer after the long message."))
        let context = startResponse(test, source: source)
        let snapshot = try XCTUnwrap(context.snapshots.first)
        XCTAssertLessThanOrEqual(snapshot.title.utf8.count, 120)

        let reconstructed = try readAll(source.id, context: context, model: test.model)

        XCTAssertEqual(Array(reconstructed.utf8), Array(snapshot.text.utf8))
        XCTAssertTrue(reconstructed.hasSuffix(source.messages[1].content))
        let end = try decode(test.model.executeLinkedChatTool(
            read(source.id, offset: snapshot.text.unicodeScalars.count), context: context
        ))
        XCTAssertTrue(end.snapshot.text.isEmpty)
        XCTAssertNil(end.nextOffset)
    }

    func testEmptyTranscriptHasATerminalPageAndCapturedTextStaysStableUntilSourceDeletion() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = Conversation(title: "Empty saved chat", workspacePath: nil)
        let context = startResponse(test, source: source)
        test.model.conversations[0].title = "Later title"
        test.model.conversations[0].messages.append(ChatMessage(role: "user", content: "Later uncaptured content"))

        let page = try decode(test.model.executeLinkedChatTool(read(source.id), context: context))
        XCTAssertEqual(page.snapshot.title, source.title)
        XCTAssertTrue(page.snapshot.text.isEmpty)
        XCTAssertNil(page.nextOffset)

        test.model.conversations.removeAll { $0.id == source.id }
        XCTAssertTrue(try test.model.executeLinkedChatTool(read(source.id), context: context).isError)
    }

    func testMalformedArgumentsUnknownIDsAndInvalidOffsetsFailWithoutChangingTheChat() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = chat("Linked", text: "Visible saved text")
        let context = startResponse(test, source: source)
        let sourceArgument = DevelopmentJSONValue.string(source.id.uuidString)
        let invalidOffsets: [DevelopmentJSONValue] = [
            .number(-1), .number(0.5), .number(.infinity), .number(.nan),
            .number(Double(Int32.max) + 1), .number(50_000), .string("0"), .bool(false), .null
        ]
        var calls = invalidOffsets.map {
            DevelopmentToolCall(name: VyronLinkedChatTools.read, arguments: ["conversation_id": sourceArgument, "offset": $0])
        }
        calls += [
            DevelopmentToolCall(name: VyronLinkedChatTools.read, arguments: [:]),
            DevelopmentToolCall(name: VyronLinkedChatTools.read, arguments: ["conversation_id": .number(1)]),
            DevelopmentToolCall(name: VyronLinkedChatTools.read, arguments: ["conversation_id": .string("not-a-uuid")]),
            read(UUID()),
            DevelopmentToolCall(name: "unrelated_tool", arguments: ["conversation_id": sourceArgument]),
            DevelopmentToolCall(name: VyronLinkedChatTools.read, arguments: [
                "conversation_id": sourceArgument, "path": .string("/Outside/source")
            ])
        ]
        for call in calls {
            XCTAssertTrue(try test.model.executeLinkedChatTool(call, context: context).isError)
        }
        XCTAssertEqual(test.model.selectedConversationID, context.response.conversationID)
        XCTAssertEqual(test.model.conversations.first { $0.id == source.id }?.messages, source.messages)
    }

    func testStaleGenerationConversationMessageSelectionAndShutdownRejectReading() throws {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = chat("Linked", text: "Visible saved text")
        let context = startResponse(test, source: source)
        let invalidations: [() -> Void] = [
            {
                test.model.foregroundRun.stop()
                test.model.beginTestForegroundResponse()
            },
            {
                test.model.foregroundRun.stop()
                test.model.foregroundRun.begin(.init(
                    generationID: context.response.generationID,
                    conversationID: UUID(), messageID: context.response.messageID
                ))
            },
            {
                test.model.foregroundRun.stop()
                test.model.foregroundRun.begin(.init(
                    generationID: context.response.generationID,
                    conversationID: context.response.conversationID, messageID: UUID()
                ))
            },
            { test.model.foregroundRun.stop() },
            { test.model.selectedConversationID = source.id },
            { test.model.isShuttingDown = true }
        ]
        for invalidate in invalidations {
            test.model.foregroundRun.stop()
            test.model.foregroundRun.begin(context.response)
            test.model.selectedConversationID = context.response.conversationID
            test.model.isShuttingDown = false
            invalidate()
            XCTAssertThrowsError(try test.model.executeLinkedChatTool(read(source.id), context: context)) {
                XCTAssertTrue($0 is CancellationError)
            }
        }
        test.model.isShuttingDown = false
    }

    func testCancelledTaskCannotReadTheCapturedTranscript() async {
        let test = VyronQueueTestHarness()
        defer { test.cleanUp() }
        let source = chat("Linked", text: "Visible saved text")
        let context = startResponse(test, source: source)
        let task = Task { @MainActor in
            do {
                _ = try test.model.executeLinkedChatTool(self.read(source.id), context: context)
                return false
            } catch {
                return error is CancellationError
            }
        }
        task.cancel()
        let rejected = await task.value
        XCTAssertTrue(rejected)
    }

    func testWorkAndPlanRegisterAndExecuteTheReaderAgainstOnlyTheExplicitLinkedChat() async throws {
        for mode in [ComposerMode.agent, .plan] {
            let test = VyronQueueTestHarness()
            defer { test.cleanUp() }
            let project = test.directory.appendingPathComponent("Project", isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            try Data("Small local project.\n".utf8).write(to: project.appendingPathComponent("README.md"))
            await test.model.loadWorkspace(project)
            test.model.composer.mode = mode
            test.model.computerWork.automaticRequestRouting = false
            let source = chat("Explicit source", text: "SOURCE_VISIBLE_FACT: The chosen model uses 24 GB.")
            test.model.conversations = [source]
            test.model.selectedConversationID = nil
            test.send("Read this saved transcript and report its model memory fact: vyron://chat/\(source.id)")
            try await waitUntil { await test.provider.developmentRequests.count == 1 }
            let catalogs = await test.provider.developmentToolCatalogs
            XCTAssertTrue(try XCTUnwrap(catalogs.first).contains(VyronLinkedChatTools.definition))

            await test.provider.completeDevelopment(0, message: DevelopmentMessage(
                role: "assistant", toolCalls: [read(source.id)]
            ))
            try await waitUntil { await test.provider.developmentRequests.count == 2 }
            let messages = await test.provider.developmentRequests[1]
            let tool = try XCTUnwrap(messages.last { $0.role == "tool" && $0.toolName == VyronLinkedChatTools.read })
            let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(tool.content.utf8)) as? [String: Any])
            XCTAssertEqual(envelope["ok"] as? Bool, true)
            XCTAssertEqual(envelope["truncated"] as? Bool, false)
            let output = try XCTUnwrap(envelope["output"] as? String)
            let page = try JSONDecoder().decode(VyronLinkedChatPage.self, from: Data(output.utf8))
            XCTAssertTrue(page.snapshot.text.contains(source.messages[0].content))
            XCTAssertNil(page.nextOffset)

            await test.provider.completeDevelopment(1, message: DevelopmentMessage(
                role: "assistant", content: "The saved chat says the chosen model uses 24 GB."
            ))
            try await waitUntil { !test.model.foregroundRun.isGenerating && !test.model.foregroundRun.isStoppingDevelopment }
            XCTAssertNil(test.model.errorMessage)
            XCTAssertEqual(test.model.conversations.first { $0.id == source.id }?.messages, source.messages)
        }
    }

    private func chat(_ title: String, text: String) -> Conversation {
        var source = Conversation(title: title, workspacePath: nil)
        source.messages = [ChatMessage(role: "user", content: text)]
        return source
    }

    private func startResponse(_ test: VyronQueueTestHarness, source: Conversation) -> VyronLinkedChatToolContext {
        var current = Conversation(title: "Current chat", workspacePath: nil)
        current.messages = [ChatMessage(role: "assistant", content: "Reading the explicit reference")]
        test.model.conversations = [source, current]
        test.model.selectedConversationID = current.id
        let response = VyronResponseIdentity(
            generationID: UUID(), conversationID: current.id, messageID: current.messages[0].id
        )
        test.model.foregroundRun.begin(response)
        return test.model.linkedChatToolContext(response: response, prompt: "Read [saved chat](vyron://chat/\(source.id)).")
    }

    private func read(_ id: UUID, offset: Int? = nil) -> DevelopmentToolCall {
        var arguments: [String: DevelopmentJSONValue] = ["conversation_id": .string(id.uuidString)]
        if let offset { arguments["offset"] = .number(Double(offset)) }
        return DevelopmentToolCall(name: VyronLinkedChatTools.read, arguments: arguments, id: "linked-chat-read")
    }

    private func decode(_ result: DevelopmentExternalResult) throws -> VyronLinkedChatPage {
        XCTAssertFalse(result.isError, result.text)
        return try JSONDecoder().decode(VyronLinkedChatPage.self, from: Data(result.text.utf8))
    }

    private func readAll(_ id: UUID, context: VyronLinkedChatToolContext, model: AppModel) throws -> String {
        var reconstructed = ""
        var offset = 0
        for _ in 0..<200 {
            let result = try model.executeLinkedChatTool(read(id, offset: offset), context: context)
            XCTAssertLessThanOrEqual(result.text.utf8.count, VyronLinkedChatTools.maximumResultBytes)
            let wrapped = try JSONSerialization.data(withJSONObject: [
                "ok": !result.isError, "output": result.text, "truncated": false
            ])
            XCTAssertLessThanOrEqual(wrapped.count, 4_000)
            let page = try decode(result)
            XCTAssertEqual(page.snapshot.conversationID, id)
            reconstructed += page.snapshot.text
            guard let next = page.nextOffset else { return reconstructed }
            XCTAssertEqual(next, offset + page.snapshot.text.unicodeScalars.count)
            XCTAssertGreaterThan(next, offset)
            offset = next
        }
        XCTFail("The reader did not reach the end of a bounded test transcript.")
        return reconstructed
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("The linked-chat tool did not reach the expected provider boundary.")
        throw CancellationError()
    }
}
