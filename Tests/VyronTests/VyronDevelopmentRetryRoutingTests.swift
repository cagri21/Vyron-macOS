import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronDevelopmentRetryRoutingTests: XCTestCase {
    func testRepeatedWorkRequestExcludesPriorAssistantAndCompactionClaimsFromBothInferenceStages() async throws {
        let test = try VyronAutoLocalAppTestHarness()
        defer { test.cleanUp() }
        let project = test.directory.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let source = Data("def normalize(value):\n    return value.strip().lower()\n".utf8)
        try source.write(to: project.appendingPathComponent("source.py"))
        try Data("PROJECT_GUIDANCE_CANARY: Review read-only and preserve source.\n".utf8)
            .write(to: project.appendingPathComponent("AGENTS.md"))
        await test.model.loadWorkspace(project)
        test.model.composer.mode = .agent
        await test.assessment.select(test.profile.id.uuidString)
        let constraint = ChatMessage(role: "user", content: "USER_CONSTRAINT_CANARY: Retain old records and remain read-only.")
        let goal = ChatMessage(role: "user", content: "analyze the code")
        let poison = ChatMessage(role: "assistant", content: "POISON_MODEL_CLAIM: This project implements a million-token model.")
        let snapshot = VyronConversationCompaction(
            summary: "POISON_MODEL_CLAIM: The assistant called this a comprehensive model implementation.",
            throughMessageID: poison.id
        )
        var conversation = Conversation(title: "Repeated inspection", workspacePath: project.path)
        conversation.mode = ComposerMode.agent.rawValue
        conversation.messages = [constraint, goal, poison]
        for index in 1..<8 {
            conversation.messages.append(ChatMessage(role: "user", content: goal.content))
            conversation.messages.append(ChatMessage(role: "assistant", content: "POISON_MODEL_CLAIM: repeated \(index)."))
        }
        let legacyReference = "LEGACY_REFERENCE_CANARY: User-selected local reference shared by repeated turns."
        conversation.contextByMessageID = Dictionary(uniqueKeysWithValues: conversation.messages.compactMap { message in
            message.conversationRole == .user && message.content == goal.content
                ? (message.id.uuidString, legacyReference) : nil
        })
        conversation.compaction = snapshot
        test.model.conversations = [conversation]
        test.model.selectedConversationID = conversation.id

        test.send(goal.content)
        try await test.waitUntil { !test.model.foregroundRun.isGenerating }

        let assessments = await test.assessment.requests
        let assessment = try XCTUnwrap(assessments.first)
        XCTAssertEqual(assessments.count, 1)
        let assessmentText = (assessment.context.messages.map(\.content) + [assessment.context.reference])
            .joined(separator: "\n")
        XCTAssertFalse(assessmentText.contains("POISON_MODEL_CLAIM"))
        XCTAssertTrue(assessmentText.contains("USER_CONSTRAINT_CANARY"))
        XCTAssertTrue(assessmentText.contains("LEGACY_REFERENCE_CANARY"))
        XCTAssertTrue(assessment.context.messages.contains { $0.content == goal.content })
        let requests = await test.hosted.developmentRequests
        XCTAssertEqual(requests.count, 1)
        let native = try XCTUnwrap(requests.first)
        let nativeText = native.map(\.content).joined(separator: "\n")
        XCTAssertFalse(nativeText.contains("POISON_MODEL_CLAIM"))
        XCTAssertTrue(nativeText.contains("USER_CONSTRAINT_CANARY"))
        XCTAssertTrue(nativeText.contains("PROJECT_GUIDANCE_CANARY"))
        XCTAssertTrue(native.contains { $0.role == "user" && $0.content.contains(goal.content) })
        let stored = try XCTUnwrap(test.model.conversations.first { $0.id == conversation.id })
        XCTAssertEqual(Array(stored.messages.prefix(conversation.messages.count)), conversation.messages)
        XCTAssertEqual(stored.messages.first { $0.id == poison.id }, poison)
        XCTAssertEqual(stored.compaction, snapshot)
        for (id, reference) in conversation.contextByMessageID ?? [:] {
            XCTAssertEqual(stored.contextByMessageID?[id], reference)
        }
        XCTAssertEqual(stored.messages.last?.content, "Auto Local work answer")
        XCTAssertEqual(stored.messages.last?.activity?.state, .completed)
        XCTAssertEqual(try Data(contentsOf: project.appendingPathComponent("source.py")), source)
    }
}
