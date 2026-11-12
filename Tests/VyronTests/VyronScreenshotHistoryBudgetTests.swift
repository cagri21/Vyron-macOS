import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronScreenshotHistoryBudgetTests: XCTestCase {
    func testTwoAndFourImagesReserveContextAndPruneOldTurnsAtomically() throws {
        for count in [2, 4] {
            let images = try (0..<count).map { try VyronScreenshotTestImage.attachment(name: "Image \($0)") }
            let oldUser = ChatMessage(role: "user", content: String(repeating: "a", count: 10_000))
            let oldAnswer = ChatMessage(role: "assistant", content: String(repeating: "b", count: 10_000))
            let current = ChatMessage(role: "user", content: "Analyze these screens", images: images)
            let result = VyronConversationRequestContext.boundedHistory([oldUser, oldAnswer, current], context: [:])

            XCTAssertTrue(result.omittedOlderMessages)
            XCTAssertEqual(result.messages, [current])
            XCTAssertEqual(result.messages.last?.images, images)
            XCTAssertLessThanOrEqual(estimatedBudget(result.messages), VyronScreenshotLimits.maximumConversationBudget)
        }
    }

    func testLongProjectContextIsTrimmedWithoutChangingLatestPromptOrImages() throws {
        let images = try (0..<4).map { try VyronScreenshotTestImage.attachment(name: "Image \($0)") }
        let prompt = "Describe the selected controls. " + String(repeating: "p", count: 1_000)
        let current = ChatMessage(role: "user", content: prompt, images: images)
        let projectContext = String(repeating: "Türkçe 界 🎞️\n", count: 2_000)
        let result = VyronConversationRequestContext.boundedHistory(
            [current], context: [current.id.uuidString: projectContext]
        )
        let supplied = try XCTUnwrap(result.messages.first)

        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(supplied.id, current.id)
        XCTAssertEqual(supplied.images, images)
        XCTAssertTrue(supplied.content.hasPrefix(prompt + "\n\n<local-project-context>\n"))
        XCTAssertTrue(supplied.content.hasSuffix("\n[context truncated]\n</local-project-context>"))
        XCTAssertFalse(supplied.content.contains("�"), "Context truncation must keep valid UTF-8.")
        XCTAssertTrue(result.omittedOlderMessages)
        XCTAssertLessThanOrEqual(estimatedBudget(result.messages), VyronScreenshotLimits.maximumConversationBudget)
    }

    func testContextIsOmittedWhenNoWrapperFitsButNewestPromptAndImagesRemain() throws {
        let images = try (0..<4).map { try VyronScreenshotTestImage.attachment(name: "Image \($0)") }
        let imageBudget = images.count * VyronImageAttachment.estimatedContextTokens
        let remaining = VyronScreenshotLimits.maximumConversationBudget
            - VyronConversationRequestContext.systemPrompt.utf8.count
            - imageBudget - 80
        let prompt = String(repeating: "p", count: remaining)
        let current = ChatMessage(role: "user", content: prompt, images: images)
        let result = VyronConversationRequestContext.boundedHistory(
            [current], context: [current.id.uuidString: "Selected file"]
        )

        XCTAssertEqual(result.messages, [current])
        XCTAssertTrue(result.omittedOlderMessages)
        XCTAssertEqual(estimatedBudget(result.messages), VyronScreenshotLimits.maximumConversationBudget)
    }

    func testOversizedRestoredNewestTurnIsRetainedForExplicitProviderValidation() throws {
        let image = try VyronScreenshotTestImage.attachment()
        let current = ChatMessage(
            role: "user", content: String(repeating: "p", count: 24_000), images: [image]
        )
        let result = VyronConversationRequestContext.boundedHistory(
            [ChatMessage(role: "user", content: "Older turn"), current], context: [:]
        )

        XCTAssertEqual(result.messages, [current])
        XCTAssertTrue(result.omittedOlderMessages)
    }

    private func estimatedBudget(_ messages: [ChatMessage]) -> Int {
        VyronConversationRequestContext.systemPrompt.utf8.count + messages.reduce(0) { total, message in
            total + message.content.utf8.count + 80
                + (message.images?.count ?? 0) * VyronImageAttachment.estimatedContextTokens
        }
    }
}
