import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronCapturedImageArtifactTests: XCTestCase {
    func testLegacyMessagesDecodeWithoutCaptureArtifacts() throws {
        let legacy = """
        {"id":"AF4E2C13-01BF-4B90-9A74-7E79AAC80F18","role":"assistant","content":"Ready."}
        """

        let decoded = try JSONDecoder().decode(ChatMessage.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.content, "Ready.")
        XCTAssertNil(decoded.images)
        XCTAssertNil(decoded.capturedImages)
    }

    func testCapturedScreenshotsRoundTripSeparatelyFromUserAttachments() throws {
        let image = capture()
        var message = ChatMessage(role: "assistant", content: "Checked the app.")
        message.capturedImages = [image]

        let encoded = try JSONEncoder().encode(message)
        let restored = try JSONDecoder().decode(ChatMessage.self, from: encoded)
        let record = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(restored, message)
        XCTAssertEqual(restored.capturedImages, [image])
        XCTAssertNil(restored.images)
        XCTAssertNotNil(record["capturedImages"])
        XCTAssertNil(record["images"])
    }

    func testCapturedArtifactsAreNotImplicitModelImageInputs() throws {
        var captured = ChatMessage(role: "assistant", content: "Checked the app.")
        captured.capturedImages = [capture()]

        XCTAssertNoThrow(try VyronImageAttachment.validate(messages: [captured]))
        let wire = try VyronOpenAIResponsesWire.chatInput([captured], systemPrompt: nil)

        XCTAssertEqual(wire, [.object([
            "role": .string("assistant"), "content": .string("Checked the app.")
        ])])
    }

    func testUserImagesKeepTheirExistingModelInputBehavior() throws {
        let image = capture()
        let message = ChatMessage(role: "user", content: "Inspect this screenshot.", images: [image])
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))

        XCTAssertEqual(decoded.images, [image])
        XCTAssertNil(decoded.capturedImages)
        XCTAssertNoThrow(try VyronImageAttachment.validate(messages: [decoded]))
        let wire = try VyronOpenAIResponsesWire.chatInput([decoded], systemPrompt: nil)
        guard case .object(let item) = try XCTUnwrap(wire.first),
            case .array(let parts) = item["content"] else {
            return XCTFail("User attachments must remain image model inputs.")
        }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.last, .object([
            "type": .string("input_image"),
            "image_url": .string("data:image/png;base64,\(image.data.base64EncodedString())")
        ]))
    }

    private func capture() -> VyronImageAttachment {
        VyronImageAttachment(
            name: "Automatic capture.png",
            mimeType: "image/png",
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        )
    }
}
