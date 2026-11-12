import Foundation
import XCTest
@testable import VyronCore

final class VyronConversationCompactionBuilderTests: XCTestCase {
    func testEmptyHistoryAndAlreadyCoveredHistoryDoNotRequestAnotherSummary() throws {
        XCTAssertNil(try VyronConversationCompactionContext.prepare(VyronConversationCompactionInput(messages: [])))
        let message = ChatMessage(role: "user", content: "Original goal")
        let previous = VyronConversationCompaction(summary: "Goal retained", throughMessageID: message.id)

        XCTAssertNil(try VyronConversationCompactionContext.prepare(
            VyronConversationCompactionInput(messages: [message], previous: previous)
        ))
    }

    func testPreparationIncludesUserIntentContextSnapshotsAndLastBoundary() throws {
        let first = ChatMessage(role: "user", content: "Build the screen with blue accents")
        let second = ChatMessage(role: "assistant", content: "The screen is implemented; tests not run")
        let latest = ChatMessage(role: "user", content: "Use rounded controls and keep the saved layout")
        let context = "Sources/Screen.swift contains the current implementation"
        let request = try XCTUnwrap(VyronConversationCompactionContext.prepare(VyronConversationCompactionInput(
            messages: [first, second, latest],
            contextByMessageID: [first.id.uuidString: context]
        )))
        let text = try XCTUnwrap(request.messages.first?.content)

        XCTAssertTrue(text.contains(first.content))
        XCTAssertTrue(text.contains(second.content))
        XCTAssertTrue(text.contains(latest.content))
        XCTAssertTrue(text.contains(context))
        XCTAssertTrue(text.contains("Context snapshot"))
        XCTAssertFalse(request.wasTruncated)
        XCTAssertEqual(request.throughMessageID, latest.id)
        assertBounded(request, bytes: 18_000)
    }

    func testSummaryRequestIncludesAttachmentNamesAndNeverImagePixels() throws {
        let image = VyronImageAttachment(name: "actual-app.png", mimeType: "image/png", data: Data("PRIVATE_PIXELS".utf8))
        let user = ChatMessage(role: "user", content: "Review this screen", images: [image])
        let request = try XCTUnwrap(VyronConversationCompactionContext.prepare(
            VyronConversationCompactionInput(messages: [user])
        ))
        let text = try XCTUnwrap(request.messages.first?.content)

        XCTAssertTrue(text.contains("actual-app.png"))
        XCTAssertTrue(text.contains("pixels unavailable"))
        XCTAssertFalse(text.contains("PRIVATE_PIXELS"))
        XCTAssertFalse(text.contains(image.data.base64EncodedString()))
        XCTAssertTrue(request.messages.allSatisfy { ($0.images ?? []).isEmpty })
    }

    func testRepeatedCompactionIncludesPreviousSummaryAndOnlyNewTranscript() throws {
        let oldUser = ChatMessage(role: "user", content: "OLD_RAW_TRANSCRIPT")
        let oldReply = ChatMessage(role: "assistant", content: "Old reply")
        let previous = VyronConversationCompaction(summary: "Existing verified state", throughMessageID: oldReply.id)
        let newerUser = ChatMessage(role: "user", content: "Now add a compact picker")
        let newerReply = ChatMessage(role: "assistant", content: "Picker completed locally")
        let request = try XCTUnwrap(VyronConversationCompactionContext.prepare(VyronConversationCompactionInput(
            messages: [oldUser, oldReply, newerUser, newerReply],
            contextByMessageID: [newerUser.id.uuidString: "Current picker file"],
            previous: previous
        )))
        let text = try XCTUnwrap(request.messages.first?.content)

        XCTAssertTrue(text.contains(previous.summary))
        XCTAssertTrue(text.contains(newerUser.content))
        XCTAssertTrue(text.contains(newerReply.content))
        XCTAssertFalse(text.contains(oldUser.content))
        XCTAssertTrue(text.contains("Current picker file"))
        XCTAssertEqual(request.throughMessageID, newerReply.id)

        let next = ChatMessage(role: "user", content: "The next complete user request")
        let updated = VyronConversationCompaction(summary: "Updated verified state", throughMessageID: request.throughMessageID)
        let inference = VyronConversationCompactionContext.inferenceMessages(
            [oldUser, oldReply, newerUser, newerReply, next], compaction: updated
        )
        XCTAssertEqual(Array(inference.dropFirst()), [next])
    }

    func testMissingPreviousBoundarySummarizesFullHistoryWithoutUsingStaleSummary() throws {
        let message = ChatMessage(role: "user", content: "Actual original goal")
        let previous = VyronConversationCompaction(summary: "STALE_SUMMARY", throughMessageID: UUID())
        let request = try XCTUnwrap(VyronConversationCompactionContext.prepare(
            VyronConversationCompactionInput(messages: [message], previous: previous)
        ))

        XCTAssertTrue(request.messages[0].content.contains(message.content))
        XCTAssertFalse(request.messages[0].content.contains(previous.summary))
    }

    func testUserIntentAndSnapshotsTakePriorityOverLargeAssistantClaims() throws {
        let first = ChatMessage(role: "user", content: "Original intent: keep all saved preferences")
        let huge = ChatMessage(role: "assistant", content: String(repeating: "Assistant claim ", count: 10_000))
        let correction = ChatMessage(role: "user", content: "Correction: use blue and never change credentials")
        let latestText = String(repeating: "Latest üser goal. ", count: 50)
        let latest = ChatMessage(role: "user", content: latestText)
        let request = try XCTUnwrap(VyronConversationCompactionContext.prepare(VyronConversationCompactionInput(
            messages: [first, huge, correction, huge, latest],
            contextByMessageID: [latest.id.uuidString: "Verified current source path"]
        ), maximumBytes: 8_000))
        let text = request.messages[0].content

        XCTAssertTrue(text.contains(first.content))
        XCTAssertTrue(text.contains(correction.content))
        XCTAssertTrue(text.contains(latestText))
        XCTAssertTrue(text.contains("Verified current source path"))
        XCTAssertTrue(request.wasTruncated)
        assertBounded(request, bytes: 8_000)
    }

    func testMultibyteExcerptBudgetNeverSplitsUTF8AndKeepsLatestPromptComplete() throws {
        let old = ChatMessage(role: "user", content: String(repeating: "🎬é", count: 10_000))
        let latest = ChatMessage(role: "user", content: "Keep this entire latest request: çağrı")
        let request = try XCTUnwrap(VyronConversationCompactionContext.prepare(
            VyronConversationCompactionInput(messages: [old, latest]), maximumBytes: 3_000
        ))

        XCTAssertTrue(request.messages[0].content.contains(latest.content))
        XCTAssertFalse(request.messages[0].content.contains("\u{FFFD}"))
        XCTAssertTrue(request.wasTruncated)
        assertBounded(request, bytes: 3_000)
    }

    func testPreviousSummaryRemainsWholeWhenNewTranscriptNeedsClipping() throws {
        let old = ChatMessage(role: "assistant", content: "Old completed response")
        let summary = String(repeating: "Retained earlier fact. ", count: 250)
        let previous = VyronConversationCompaction(summary: summary, throughMessageID: old.id)
        let latest = ChatMessage(role: "user", content: "Latest complete goal")
        let huge = ChatMessage(role: "assistant", content: String(repeating: "New assistant content ", count: 10_000))
        let request = try XCTUnwrap(VyronConversationCompactionContext.prepare(
            VyronConversationCompactionInput(messages: [old, latest, huge], previous: previous), maximumBytes: 10_000
        ))

        XCTAssertTrue(request.messages[0].content.contains(summary.trimmingCharacters(in: .whitespacesAndNewlines)))
        XCTAssertTrue(request.messages[0].content.contains(latest.content))
        XCTAssertTrue(request.wasTruncated)
        assertBounded(request, bytes: 10_000)
    }

    func testPreparationRejectsUnfittableLatestUserOrPreviousSummaryRatherThanSilentlyLosingThem() {
        let huge = ChatMessage(role: "user", content: String(repeating: "a", count: 20_000))
        XCTAssertThrowsError(try VyronConversationCompactionContext.prepare(VyronConversationCompactionInput(messages: [huge]))) {
            XCTAssertEqual($0 as? VyronConversationCompactionError, .inputTooLarge)
        }
        let old = ChatMessage(role: "user", content: "Original")
        let latest = ChatMessage(role: "user", content: "New goal")
        let previous = VyronConversationCompaction(summary: String(repeating: "a", count: 6_001), throughMessageID: old.id)
        XCTAssertThrowsError(try VyronConversationCompactionContext.prepare(
            VyronConversationCompactionInput(messages: [old, latest], previous: previous)
        )) {
            XCTAssertEqual($0 as? VyronConversationCompactionError, .summaryTooLarge)
        }
        XCTAssertThrowsError(try VyronConversationCompactionContext.prepare(
            VyronConversationCompactionInput(messages: [latest]), maximumBytes: Int.min
        )) {
            XCTAssertEqual($0 as? VyronConversationCompactionError, .inputTooLarge)
        }
    }

    private func assertBounded(_ request: VyronConversationCompactionRequest, bytes: Int) {
        let contentBytes = request.messages.reduce(0) { $0 + $1.content.utf8.count }
        XCTAssertLessThanOrEqual(contentBytes + VyronConversationCompactionContext.summarySystemPrompt.utf8.count, bytes)
    }
}
