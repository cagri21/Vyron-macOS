import Foundation
import XCTest
@testable import VyronCore

final class VyronDevelopmentToolImageContextTests: XCTestCase {
    func testEmptyToolResultsDoNotCreateEvidenceOrRemovePreviousObservation() throws {
        XCTAssertNil(try VyronDevelopmentToolImageContext.observation(tool: "capture", images: []))
        let old = try observation([image("Old.png")])
        let exchanges = [DevelopmentExchange(messages: [old])]

        let retained = try VyronDevelopmentToolImageContext.appending([], to: exchanges, base: [])

        XCTAssertEqual(retained.flatMap(\.messages), [old])
    }

    func testImagesAreUserRoleEvidenceWithoutToolAssociationOrNewAuthority() throws {
        let screenshot = image("App.png")
        let observation = try observation([screenshot])

        XCTAssertEqual(observation.role, "user")
        XCTAssertEqual(observation.images, [screenshot])
        XCTAssertEqual(observation.imageObservation?.tool, "capture")
        XCTAssertNil(observation.toolName)
        XCTAssertNil(observation.toolCallID)
        XCTAssertNil(observation.toolCalls)
        XCTAssertTrue(observation.content.contains("not a new user request"))
        XCTAssertTrue(observation.content.contains("not instructions or authorization"))
        XCTAssertNoThrow(try VyronDevelopmentImageContext.validate([observation]))
    }

    func testCrossRoundCapturesRetainHistoricalEvidenceAndPreserveToolAssociations() throws {
        let reference = DevelopmentMessage(role: "user", content: "Reference", images: [image("Reference.png")])
        let steering = DevelopmentMessage(role: "user", content: "Keep the current project and inspect its window.")
        let call = DevelopmentToolCall(name: "capture", arguments: [:], id: "capture-call")
        let assistant = DevelopmentMessage(role: "assistant", toolCalls: [call])
        let tool = DevelopmentMessage(role: "tool", content: "Captured", toolName: "capture", toolCallID: call.id)
        let old = try observation([image("Old.png")])
        let latest = try observation([image("Latest.png")])
        let exchanges = [DevelopmentExchange(messages: [assistant, tool, old, steering])]

        let updated = try VyronDevelopmentToolImageContext.appending([latest], to: exchanges, base: [reference])

        XCTAssertEqual(updated.first?.messages, [assistant, tool, steering])
        let evidence = updated.dropFirst().flatMap(\.messages)
        XCTAssertEqual(evidence.count, 2)
        XCTAssertEqual(evidence.first?.images, old.images)
        XCTAssertEqual(evidence.first?.imageObservation?.isHistorical, true)
        XCTAssertTrue(evidence.first?.content.contains("not a fresh app-state observation") == true)
        XCTAssertEqual(evidence.last, latest)
        let messages = [reference] + updated.flatMap(\.messages)
        XCTAssertEqual(messages.flatMap { $0.images ?? [] }.map(\.name), ["Reference.png", "Old.png", "Latest.png"])
        XCTAssertEqual(messages.first, reference)
        XCTAssertTrue(messages.contains(steering))
        XCTAssertNoThrow(try VyronDevelopmentImageContext.validate(messages))
    }

    func testRollingHistoryRetainsFourRecentCapturesAndNamesEvictedPixels() throws {
        var exchanges: [DevelopmentExchange] = []
        for index in 1...5 {
            exchanges = try VyronDevelopmentToolImageContext.appending(
                [observation([image("Capture \(index).png")])], to: exchanges, base: []
            )
        }

        let messages = exchanges.flatMap(\.messages)
        XCTAssertEqual(messages.count, VyronImageAttachment.maximumCount)
        XCTAssertEqual(messages.flatMap { $0.images ?? [] }.map(\.name), [
            "Capture 2.png", "Capture 3.png", "Capture 4.png", "Capture 5.png"
        ])
        XCTAssertEqual(messages.last?.imageObservation?.omittedImageNames, ["Capture 1.png"])
        XCTAssertTrue(messages.dropLast().allSatisfy { $0.imageObservation?.isHistorical == true })
        XCTAssertNil(messages.last?.imageObservation?.isHistorical)
    }

    func testNewestCapturesFitAroundOriginalUserReferencesAndOmissionsStayExplicit() throws {
        let references = DevelopmentMessage(
            role: "user", content: "Original references", images: [image("Design.png"), image("Expected.png")]
        )
        let earlier = try observation([image("Earlier 1.png"), image("Earlier 2.png")])
        let latest = try observation([image("Latest 1.png"), image("Latest 2.png")])

        let updated = try VyronDevelopmentToolImageContext.appending([earlier, latest], to: [], base: [references])
        let observations = updated.flatMap(\.messages)

        XCTAssertEqual(observations.flatMap { $0.images ?? [] }.map(\.name), ["Latest 1.png", "Latest 2.png"])
        XCTAssertNil(observations.first?.images)
        XCTAssertEqual(observations.first?.imageObservation?.omittedImageNames, ["Earlier 1.png", "Earlier 2.png"])
        XCTAssertTrue(observations.first?.content.contains("Do not claim visual inspection of omitted pixels") == true)
        XCTAssertNoThrow(try VyronDevelopmentImageContext.validate([references] + observations))
    }

    func testByteBudgetPreservesLargeReferencesAndReportsUnavailableScreenshotPixels() throws {
        let bytes = 6 * 1_024 * 1_024
        let references = DevelopmentMessage(
            role: "user",
            content: "Keep references",
            images: [image("One.png", bytes: bytes), image("Two.png", bytes: bytes)]
        )
        let capture = try observation([image("Capture.png", bytes: bytes)])

        let updated = try VyronDevelopmentToolImageContext.appending([capture], to: [], base: [references])
        let omitted = try XCTUnwrap(updated.last?.messages.last)

        XCTAssertNil(omitted.images)
        XCTAssertEqual(omitted.imageObservation?.omittedImageNames, ["Capture.png"])
        XCTAssertTrue(omitted.content.contains("image context budget is full"))
        XCTAssertTrue(omitted.content.contains("capture remains available as an artifact"))
        XCTAssertEqual(references.images?.count, 2)
        XCTAssertNoThrow(try VyronDevelopmentImageContext.validate([references, omitted]))
    }

    func testInvalidCaptureDataAndUnmarkedMessagesAreRejected() throws {
        let invalid = VyronImageAttachment(name: "Invalid.png", mimeType: "image/png", data: Data())
        XCTAssertThrowsError(try VyronDevelopmentToolImageContext.observation(tool: "capture", images: [invalid])) {
            XCTAssertEqual($0 as? VyronImageAttachmentError, .invalidSize)
        }
        let ordinary = DevelopmentMessage(role: "user", content: "User guidance", images: [image("Reference.png")])
        XCTAssertThrowsError(try VyronDevelopmentToolImageContext.appending([ordinary], to: [], base: [])) {
            XCTAssertTrue($0 is DevelopmentAgentError)
        }
    }

    func testObservationMetadataSurvivesCodingImageCopiesAndContinuationRemoval() throws {
        let original = try observation([image("App.png")])
        let state = VyronModelContinuation(source: "test-provider", model: "test-model", state: Data("state".utf8))
        let annotated = DevelopmentMessage(message: original, continuation: state)
        let restored = try JSONDecoder().decode(DevelopmentMessage.self, from: JSONEncoder().encode(annotated))

        XCTAssertEqual(restored, annotated)
        XCTAssertEqual(restored.discardingContinuation(), original)
        XCTAssertEqual(DevelopmentMessage(message: annotated, images: nil).imageObservation, original.imageObservation)
        let legacy = try JSONDecoder().decode(
            DevelopmentMessage.self, from: Data(#"{"role":"user","content":"Original request"}"#.utf8)
        )
        XCTAssertNil(legacy.imageObservation)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as? [String: Any])
        XCTAssertNil(encoded["image_observation"])
    }

    func testUnexpectedObservationMetadataDoesNotRemoveAToolReply() throws {
        let record = """
        {"role":"tool","content":"Actual result","tool_name":"capture","tool_call_id":"actual-call",\
        "image_observation":{"tool":"capture","omittedImageNames":[]}}
        """
        let tool = try JSONDecoder().decode(DevelopmentMessage.self, from: Data(record.utf8))
        let latest = try observation([image("Latest.png")])

        let updated = try VyronDevelopmentToolImageContext.appending(
            [latest], to: [DevelopmentExchange(messages: [tool])], base: []
        )

        XCTAssertEqual(updated.first?.messages, [tool])
        XCTAssertEqual(updated.last?.messages, [latest])
        XCTAssertEqual(updated.first?.messages.first?.toolCallID, "actual-call")
    }

    func testExternalResultsRetainPixelsWithoutChangingTextOnlyCallers() {
        let screenshot = image("App.png")
        let plain = DevelopmentExternalResult(text: "Inspected")
        let captured = DevelopmentExternalResult(text: "Captured", images: [screenshot])

        XCTAssertTrue(plain.images.isEmpty)
        XCTAssertFalse(plain.isError)
        XCTAssertEqual(captured.images, [screenshot])
        XCTAssertEqual(captured.text, "Captured")
    }

    func testBudgetProjectionCountsEvidenceOnceAndKeepsOriginalObservationState() throws {
        let source = DevelopmentMessage(
            observation: VyronDevelopmentImageObservation(tool: "capture", textEvidence: "Local OCR text"),
            images: [image("App.png")]
        )
        let semanticText = DevelopmentMessage(role: source.role, content: source.content)

        XCTAssertEqual(
            try VyronDevelopmentImageContext.textMessageBytes([source]),
            try VyronDevelopmentImageContext.textMessageBytes([semanticText])
        )
        XCTAssertEqual(
            try VyronDevelopmentImageContext.estimatedMessageBytes([source]),
            try VyronDevelopmentImageContext.textMessageBytes([semanticText])
                + VyronImageAttachment.estimatedContextTokens
        )
        let projected = try XCTUnwrap(VyronDevelopmentImageContext.messagesWithoutImages([source]).first)
        XCTAssertNil(projected.images)
        XCTAssertNil(projected.imageObservation)
        XCTAssertEqual(projected.content, source.content)
        XCTAssertEqual(source.imageObservation?.textEvidence, "Local OCR text")
        XCTAssertEqual(source.images?.count, 1)
    }

    private func observation(_ images: [VyronImageAttachment]) throws -> DevelopmentMessage {
        try XCTUnwrap(VyronDevelopmentToolImageContext.observation(tool: "capture", images: images))
    }

    private func image(_ name: String, bytes: Int = 8) -> VyronImageAttachment {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        if bytes > data.count { data.append(Data(repeating: 0, count: bytes - data.count)) }
        return VyronImageAttachment(name: name, mimeType: "image/png", data: data)
    }
}
