import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore
@testable import Vyron

@MainActor
final class VyronClarificationHistoryTests: XCTestCase {
    private var directory: URL!
    private var model: AppModel!
    private let goal = "Create a minimal iOS template app."
    private let start = Date(timeIntervalSince1970: 1_000)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronClarificationHistory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        model = AppModel(historyDirectory: directory)
        var conversation = Conversation(title: "Clarification ownership", workspacePath: nil)
        let assistant = ChatMessage(role: "assistant", content: "", activity: ResponseActivity(startedAt: start))
        conversation.messages = [ChatMessage(role: "user", content: goal), assistant]
        model.conversations = [conversation]
        model.selectedConversationID = conversation.id
        model.beginTestForegroundResponse()
    }

    override func tearDown() async throws {
        model.stopGeneration()
        model = nil
        try FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testActualClarificationPreservesOriginalGoalGuidanceAndResponseLineage() async throws {
        let responseID = try XCTUnwrap(model.foregroundRun.activeResponse?.messageID)
        try await completeClarification()
        let history = model.messages + [ChatMessage(role: "user", content: "Continue")]

        let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: history))

        XCTAssertEqual(context.originalGoal, goal)
        XCTAssertEqual(context.priorResponseIDs, [responseID])
        XCTAssertEqual(context.guidance, ["Which accent color?\nBlue"])
    }

    func testActualClarificationKeepsTheTaskTimestampOnTheOriginalUserTurn() async throws {
        let originalUserID = try XCTUnwrap(model.messages.first?.id)
        try await completeClarification()
        let answerID = model.messages[2].id

        let timeline = VyronConversationTimeline(messages: model.messages)

        XCTAssertEqual(timeline.startDatesByMessageID[originalUserID], start)
        XCTAssertNil(timeline.startDatesByMessageID[answerID])
    }

    func testActualClarificationOwnershipRoundTripsAndSurvivesReopening() async throws {
        let responseID = try XCTUnwrap(model.foregroundRun.activeResponse?.messageID)
        try await completeClarification()
        for message in model.messages[1...2] {
            // Inspect the persisted JSON boundary without requiring a new construction parameter.
            let fields = try JSONDecoder().decode(
                [String: DevelopmentJSONValue].self, from: JSONEncoder().encode(message)
            )
            XCTAssertEqual(fields["parentResponseID"], .string(responseID.uuidString))
            let restored = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
            XCTAssertEqual(restored, message)
        }
        let reopened = AppModel(historyDirectory: directory)
        let savedMessages = try XCTUnwrap(reopened.conversations.first?.messages)
        let history = savedMessages + [ChatMessage(role: "user", content: "Continue")]

        let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: history))

        XCTAssertEqual(context.originalGoal, goal)
        XCTAssertEqual(context.priorResponseIDs, [responseID])
        XCTAssertEqual(context.guidance, ["Which accent color?\nBlue"])
        XCTAssertEqual(savedMessages[2].clarificationAnswers, [
            VyronClarificationAnswer(question: "Which accent color?", answer: "Blue")
        ])
        XCTAssertEqual(VyronConversationTimeline(messages: savedMessages).startDatesByMessageID[savedMessages[0].id], start)
    }

    func testSubmittedClarificationsKeepMultilineRepliesInQuestionOrder() async throws {
        try await completeClarification(
            questions: [
                VyronUserInputQuestion(id: "accent", question: "Which accent color?\n\nGive one color."),
                VyronUserInputQuestion(id: "settings", question: "Where should it appear?")
            ],
            answers: [
                VyronUserInputAnswer(questionID: "settings", value: "Only in Settings."),
                VyronUserInputAnswer(questionID: "accent", value: "Blue.\n\nMatch the icon.")
            ]
        )

        let messages = model.messages
        let transcript = VyronConversationTranscript(messages: messages)
        XCTAssertEqual(transcript.rows.map(\.id), [messages[0].id, messages[2].id, messages[3].id])
        XCTAssertEqual(transcript.rows[1].clarificationAnswers, [
            VyronClarificationAnswer(question: "Which accent color?\n\nGive one color.", answer: "Blue.\n\nMatch the icon."),
            VyronClarificationAnswer(question: "Where should it appear?", answer: "Only in Settings.")
        ])
        XCTAssertEqual(messages[2].content, """
            Which accent color?

            Give one color.
            Blue.

            Match the icon.

            Where should it appear?
            Only in Settings.
            """)
    }

    func testRepeatedClarificationsKeepOneResponseOwnerAndOneTaskTimestamp() async throws {
        let responseID = try XCTUnwrap(model.foregroundRun.activeResponse?.messageID)
        let originalUserID = try XCTUnwrap(model.messages.first?.id)
        try await completeClarification()
        try await completeClarification()
        let history = model.messages + [ChatMessage(role: "user", content: "Continue")]

        let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: history))
        let timeline = VyronConversationTimeline(messages: history)

        XCTAssertEqual(context.originalGoal, goal)
        XCTAssertEqual(context.priorResponseIDs, [responseID])
        XCTAssertEqual(context.guidance, ["Which accent color?\nBlue", "Which accent color?\nBlue"])
        XCTAssertEqual(timeline.startDatesByMessageID, [originalUserID: start])
    }

    func testUnmarkedLegacyAssistantStillSeparatesRealUserTasks() throws {
        let old = ChatMessage(role: "assistant", content: "An actual legacy response without activity.")
        let latestGoal = "Create a different iOS template app."
        let latestUser = ChatMessage(role: "user", content: latestGoal)
        let latest = ChatMessage(role: "assistant", content: "Current work.", activity: ResponseActivity(startedAt: start))
        let history = [
            ChatMessage(role: "user", content: "Explain an unrelated earlier task."), old,
            latestUser, latest, ChatMessage(role: "user", content: "Continue")
        ]

        let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: history))

        XCTAssertEqual(context.originalGoal, latestGoal)
        XCTAssertEqual(context.priorResponseIDs, [latest.id])
        XCTAssertTrue(context.guidance.isEmpty)
        XCTAssertEqual(VyronConversationTimeline(messages: history).startDatesByMessageID[latestUser.id], start)
    }

    func testForeignAndOrphanMarkersRemainLegacyResponseBoundaries() throws {
        for owner in [UUID(), try XCTUnwrap(model.foregroundRun.activeResponse?.messageID)] {
            let legacy = try markedMessage(role: "assistant", content: "A legacy response.", owner: owner)
            let latestUser = ChatMessage(role: "user", content: "Create a separate project note.")
            let latest = ChatMessage(role: "assistant", content: "Note progress.", activity: ResponseActivity(startedAt: start))
            let history = [
                ChatMessage(role: "user", content: "An unrelated earlier request."), legacy,
                latestUser, latest, ChatMessage(role: "user", content: "Continue")
            ]

            let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: history))

            XCTAssertEqual(context.originalGoal, latestUser.content)
            XCTAssertEqual(context.priorResponseIDs, [latest.id])
            XCTAssertTrue(context.guidance.isEmpty)
            XCTAssertEqual(VyronConversationTimeline(messages: history).startDatesByMessageID[latestUser.id], start)
        }
    }

    func testLegacyJSONWithoutOwnershipKeyStillDecodes() throws {
        let id = UUID()
        let data = try JSONSerialization.data(withJSONObject: [
            "id": id.uuidString, "role": "assistant", "content": "A saved legacy answer."
        ])

        let restored = try JSONDecoder().decode(ChatMessage.self, from: data)
        let encoded = try JSONDecoder().decode(
            [String: DevelopmentJSONValue].self, from: JSONEncoder().encode(restored)
        )

        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.content, "A saved legacy answer.")
        XCTAssertNil(encoded["parentResponseID"])
    }

    func testBackwardOwnerReferenceDoesNotHideALegacyAssistantBoundary() throws {
        let earlierOwner = ChatMessage(role: "assistant", content: "An earlier real response.")
        let backwardChild = try markedMessage(role: "assistant", content: "A separate response.", owner: earlierOwner.id)
        let latestUser = ChatMessage(role: "user", content: "Create a separate project note.")
        let latest = ChatMessage(role: "assistant", content: "Current progress.", activity: ResponseActivity(startedAt: start))
        let history = [
            ChatMessage(role: "user", content: "An earlier request."), earlierOwner, backwardChild,
            latestUser, latest, ChatMessage(role: "user", content: "Continue")
        ]

        let context = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(for: "Continue", messages: history))

        XCTAssertEqual(context.originalGoal, latestUser.content)
        XCTAssertEqual(context.priorResponseIDs, [latest.id])
        XCTAssertEqual(VyronConversationTimeline(messages: history).startDatesByMessageID[latestUser.id], start)
    }

    func testActualCoreAndAppClarificationGuidanceStopsGrowingAcrossRepeatedContinues() async throws {
        let conversationID = try XCTUnwrap(model.selectedConversationID)
        let originalResponseID = try XCTUnwrap(model.foregroundRun.activeResponse?.messageID)
        let request = try await completeClarification()
        let response = VyronUserInputResponse(requestID: request.id, answers: [
            VyronUserInputAnswer(questionID: "accent", value: "Blue")
        ])
        let coreGuidance = try VyronUserInputTool.answerContext(request: request, response: response)
        let readableGuidance = model.messages[2].content
        XCTAssertNotEqual(coreGuidance, readableGuidance)
        let projectURL = directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let project = try DevelopmentWorkspace(rootURL: projectURL)
        let store = try VyronDevelopmentTaskStore(
            directoryURL: project.taskStateDirectoryURL.appendingPathComponent(conversationID.uuidString),
            projectPath: project.rootURL.path
        )
        var checkpoint = VyronDevelopmentTaskState(identity: VyronDevelopmentTaskIdentity(
            id: originalResponseID, projectPath: project.rootURL.path, originalGoal: goal
        ))
        try checkpoint.recordGuidance(coreGuidance)
        try checkpoint.recordFile(VyronDevelopmentFileProgress(
            path: "Note.txt", contentHash: VyronDevelopmentFileProgress.hash(content: "Saved note")
        ))
        checkpoint.finish(.failed, detail: "The original task remains unfinished.")
        try store.save(checkpoint)
        let originalFiles = checkpoint.progress.files
        var transcript = model.messages

        for _ in 0..<8 {
            transcript.append(ChatMessage(role: "user", content: "Continue"))
            let continuation = try XCTUnwrap(VyronDevelopmentContinuationHistory.context(
                for: "Continue", messages: transcript
            ))
            let responseID = UUID()
            var progress = try VyronDevelopmentRunProgress(
                workspace: project,
                session: VyronDevelopmentSessionContext(
                    conversationID: conversationID, responseID: responseID, continuation: continuation
                ),
                goal: "Continue"
            )

            XCTAssertEqual(progress.state.identity.id, originalResponseID)
            XCTAssertEqual(progress.state.guidance.filter {
                !VyronDevelopmentContinuationContext.isContinuationRequest($0)
            }, [coreGuidance, readableGuidance])
            XCTAssertEqual(progress.state.progress.files, originalFiles)
            progress.state.finish(.failed, detail: "The continued task remains unfinished.")
            try progress.save()
            transcript.append(ChatMessage(id: responseID, role: "assistant", content: "Work remains unfinished."))
        }
    }

    @discardableResult
    private func completeClarification(
        questions: [VyronUserInputQuestion] = [VyronUserInputQuestion(id: "accent", question: "Which accent color?")],
        answers: [VyronUserInputAnswer] = [VyronUserInputAnswer(questionID: "accent", value: "Blue")]
    ) async throws -> VyronUserInputRequest {
        let request = VyronUserInputRequest(questions: questions)
        let generationID = try XCTUnwrap(model.foregroundRun.activeGeneration)
        let waiting = Task { try await model.requestDevelopmentUserInput(request, generationID: generationID) }
        for _ in 0..<100 {
            if model.interactions.pendingUserInput?.id == request.id { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(model.interactions.pendingUserInput?.id, request.id)
        model.respondToUserInput(VyronUserInputResponse(requestID: request.id, answers: answers))
        _ = try await waiting.value
        return request
    }

    private func markedMessage(role: String, content: String, owner: UUID) throws -> ChatMessage {
        let message = ChatMessage(role: role, content: content)
        var fields = try JSONDecoder().decode(
            [String: DevelopmentJSONValue].self, from: JSONEncoder().encode(message)
        )
        fields["parentResponseID"] = .string(owner.uuidString)
        return try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(fields))
    }
}
