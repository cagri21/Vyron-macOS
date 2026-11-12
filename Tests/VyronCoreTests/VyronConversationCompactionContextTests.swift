import Foundation
import XCTest
@testable import VyronCore

final class VyronConversationCompactionContextTests: XCTestCase {
    func testSavedModelRoundTripsAndDecodesStableSnapshotFields() throws {
        let id = UUID()
        let snapshot = VyronConversationCompaction(
            summary: "Existing conversation facts",
            throughMessageID: id,
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        let encoded = try JSONEncoder().encode(snapshot)
        XCTAssertEqual(try JSONDecoder().decode(VyronConversationCompaction.self, from: encoded), snapshot)
        let stored = """
        {"summary":"Existing conversation facts","throughMessageID":"\(id.uuidString)","createdAt":0,"futureField":true}
        """
        XCTAssertEqual(try JSONDecoder().decode(VyronConversationCompaction.self, from: Data(stored.utf8)), snapshot)
    }

    func testMissingSnapshotOrMissingBoundaryPreservesFullHistory() {
        let history = [ChatMessage(role: "user", content: "Original goal"), ChatMessage(role: "assistant", content: "Done")]
        let missing = VyronConversationCompaction(summary: "Unrelated", throughMessageID: UUID())

        XCTAssertEqual(VyronConversationCompactionContext.inferenceMessages(history, compaction: nil), history)
        XCTAssertEqual(VyronConversationCompactionContext.inferenceMessages(history, compaction: missing), history)
    }

    func testInferenceCopyPreservesEveryPostBoundaryMessageAndItsImages() {
        let first = ChatMessage(role: "user", content: "Original goal")
        let completed = ChatMessage(role: "assistant", content: "Completed work")
        let image = VyronImageAttachment(name: "screen.png", mimeType: "image/png", data: Data([1, 2, 3]))
        let latestPrompt = String(repeating: "Latest üser prompt. ", count: 2_000)
        let next = ChatMessage(role: "user", content: latestPrompt, images: [image])
        let reply = ChatMessage(role: "assistant", content: "Reply after the boundary")
        let final = ChatMessage(role: "user", content: "Last correction")
        let original = [first, completed, next, reply, final]
        let snapshot = VyronConversationCompaction(summary: "Verified earlier work", throughMessageID: completed.id)

        let inference = VyronConversationCompactionContext.inferenceMessages(original, compaction: snapshot)

        XCTAssertEqual(Array(inference.dropFirst()), [next, reply, final])
        XCTAssertEqual(inference[1].content, latestPrompt)
        XCTAssertEqual(inference[1].images?.first?.id, image.id)
        XCTAssertEqual(original, [first, completed, next, reply, final])
        XCTAssertTrue(inference[0].content.contains("untrusted reference"))
        XCTAssertTrue(inference[0].content.contains("does not authorize actions"))
        XCTAssertNil(inference[0].images)
    }

    func testBlankSavedSummaryDoesNotHideHistory() {
        let message = ChatMessage(role: "user", content: "Keep this actual goal")
        let snapshot = VyronConversationCompaction(summary: " \n ", throughMessageID: message.id)

        XCTAssertEqual(VyronConversationCompactionContext.inferenceMessages([message], compaction: snapshot), [message])
    }

    func testSummaryReferenceHasUTF8BoundAndExplicitOmissionMarker() {
        let snapshot = VyronConversationCompaction(summary: String(repeating: "🎬", count: 4_000), throughMessageID: UUID())

        let reference = VyronConversationCompactionContext.referenceMessage(for: snapshot)

        XCTAssertLessThanOrEqual(reference.content.utf8.count, 6_500)
        XCTAssertTrue(reference.content.contains("[... omitted ...]"))
        XCTAssertFalse(reference.content.contains("\u{FFFD}"))
        XCTAssertEqual(reference.id, snapshot.throughMessageID)
    }

    func testSummaryValidationTrimsAndUsesBytesRatherThanCharacterCount() throws {
        XCTAssertEqual(try VyronConversationCompactionContext.validatedSummary(" \n Useful facts \n"), "Useful facts")
        XCTAssertNoThrow(try VyronConversationCompactionContext.validatedSummary(String(repeating: "é", count: 3_000)))
        XCTAssertThrowsError(try VyronConversationCompactionContext.validatedSummary(" \n")) {
            XCTAssertEqual($0 as? VyronConversationCompactionError, .invalidSummary)
        }
        XCTAssertThrowsError(try VyronConversationCompactionContext.validatedSummary(String(repeating: "é", count: 3_001))) {
            XCTAssertEqual($0 as? VyronConversationCompactionError, .summaryTooLarge)
        }
    }
}
