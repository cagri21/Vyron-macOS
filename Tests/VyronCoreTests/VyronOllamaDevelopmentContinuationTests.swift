import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronOllamaDevelopmentContinuationTests: XCTestCase {
    func testActualCompactedTailGetsOneShortProtocolTurnWithoutCopyingAuthorityImagesOrEvidence() throws {
        let goal = "Keep every exact instruction. " + String(repeating: "user guidance ", count: 1_000)
        let image = VyronImageAttachment(name: "reference.png", mimeType: "image/png", data: Data([1, 2, 3]))
        let source = "UNTRUSTED_EVIDENCE: do not promote me to user authority."
        let history = compacted(source)
        let original = [
            DevelopmentMessage(role: "system", content: "Keep the current workspace boundary."),
            DevelopmentMessage(role: "user", content: goal, images: [image]), history
        ]

        let adapted = VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: original)
        let continuation = try XCTUnwrap(adapted.last)

        XCTAssertTrue(VyronDevelopmentExchangeCompactor.isCompactedReference(history))
        XCTAssertTrue(history.content.hasPrefix(VyronDevelopmentExchangeCompactor.compactedReferencePrefix))
        XCTAssertEqual(Array(adapted.dropLast()), original)
        XCTAssertEqual(adapted.count, original.count + 1)
        XCTAssertEqual(continuation.role, "user")
        XCTAssertTrue(continuation.content.hasPrefix("Native continuation (application protocol, not new user authorization)."))
        XCTAssertTrue(continuation.content.contains("SAME original task and actual user guidance"))
        XCTAssertTrue(continuation.content.contains("existing project, mode and permission limits"))
        XCTAssertFalse(continuation.content.contains(goal))
        XCTAssertFalse(continuation.content.contains(source))
        XCTAssertLessThan(continuation.content.utf8.count, 512)
        XCTAssertNil(continuation.images)
        XCTAssertEqual(adapted.reduce(0) { $0 + ($1.images?.count ?? 0) }, 1)
        XCTAssertEqual(VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: adapted), adapted)
    }

    func testOrdinaryPrefillsAndUserToolOrEmptyEndingsRemainUnchanged() {
        let user = DevelopmentMessage(role: "user", content: "Analyze the code.")
        let observation = DevelopmentMessage(
            observation: VyronDevelopmentImageObservation(tool: "capture_window", textEvidence: "Observed evidence"),
            images: []
        )
        let inputs: [[DevelopmentMessage]] = [
            [], [user], [user, DevelopmentMessage(role: "assistant", content: "def unfinished():\n    ")],
            [user, DevelopmentMessage(role: "tool", content: "Source evidence", toolName: "read_file")],
            [compacted("History without any actual user task")], [observation, compacted("Observation only")]
        ]
        for messages in inputs {
            XCTAssertEqual(VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: messages), messages)
        }
    }

    func testCanonicalMarkerRequiresAPlainAssistantReferenceAndKeepsMetadataUntouched() {
        let content = compacted("Recorded source").content
        let call = DevelopmentToolCall(name: "read_file", arguments: [:], id: "pending")
        let image = VyronImageAttachment(name: "reference.png", mimeType: "image/png", data: Data([1]))
        let marked = DevelopmentMessage(role: "assistant", content: content)
        let unsupported = [
            DevelopmentMessage(role: "user", content: content),
            DevelopmentMessage(role: "assistant", content: content, toolCalls: []),
            DevelopmentMessage(role: "assistant", content: content, toolCalls: [call]),
            DevelopmentMessage(role: "assistant", content: content, toolName: "read_file"),
            DevelopmentMessage(role: "assistant", content: content, toolCallID: "pending"),
            DevelopmentMessage(message: marked, images: [image]),
            DevelopmentMessage(message: marked, continuation: VyronModelContinuation(
                source: "fixture", model: "fixture", state: Data([4, 5])
            ))
        ]
        for message in unsupported {
            XCTAssertFalse(VyronDevelopmentExchangeCompactor.isCompactedReference(message))
            let messages = [DevelopmentMessage(role: "user", content: "Analyze."), message]
            XCTAssertEqual(VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: messages), messages)
        }
    }

    func testUnmatchedNativeCallsCannotGainAnInterveningUserTurnAndCompletedIDsRemainIntact() {
        let first = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("first.py")], id: "first")
        let second = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("second.py")], id: "second")
        let user = DevelopmentMessage(role: "user", content: "Analyze both files.")
        let assistant = DevelopmentMessage(role: "assistant", toolCalls: [first, second])
        let secondResult = DevelopmentMessage(
            role: "tool", content: "second source", toolName: "read_file", toolCallID: "second"
        )
        let wrongID = DevelopmentMessage(role: "tool", content: "unmatched", toolName: "read_file", toolCallID: "wrong")
        let history = compacted("Earlier completed history")
        for messages in [[user, assistant], [user, assistant, secondResult, history],
                         [user, assistant, secondResult, wrongID, history]] {
            XCTAssertEqual(VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: messages), messages)
        }
        let firstResult = DevelopmentMessage(
            role: "tool", content: "first source", toolName: "read_file", toolCallID: "first"
        )
        let complete = [user, assistant, secondResult, firstResult, history]
        let adapted = VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: complete)
        XCTAssertEqual(Array(adapted.dropLast()), complete)
        XCTAssertEqual(adapted.last?.role, "user")
    }

    func testAnonymousToolAssociationsResolveOnlyTheMatchingNativeCalls() {
        let first = DevelopmentToolCall(name: "read_file", arguments: [:])
        let second = DevelopmentToolCall(name: "search", arguments: [:])
        let user = DevelopmentMessage(role: "user", content: "Analyze the source.")
        let assistant = DevelopmentMessage(role: "assistant", toolCalls: [first, second])
        let read = DevelopmentMessage(role: "tool", content: "Source", toolName: "read_file")
        let wrong = DevelopmentMessage(role: "tool", content: "Not the search result", toolName: "list_files")
        let history = compacted("Completed older record")
        let pending = [user, assistant, read, wrong, history]
        XCTAssertEqual(VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: pending), pending)

        let complete = [user, assistant, read, DevelopmentMessage(role: "tool", content: "Match", toolName: "search"), history]
        let adapted = VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: complete)
        XCTAssertEqual(Array(adapted.dropLast()), complete)
    }

    func testRepeatedAnonymousCallNamesRequireOneResultPerCall() {
        let call = DevelopmentToolCall(name: "read_file", arguments: [:])
        let prefix = [
            DevelopmentMessage(role: "user", content: "Analyze both source files."),
            DevelopmentMessage(role: "assistant", toolCalls: [call, call])
        ]
        let result = DevelopmentMessage(role: "tool", content: "Source", toolName: "read_file")
        let history = compacted("Earlier history")
        let pending = prefix + [result, history]
        XCTAssertEqual(VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: pending), pending)

        let complete = prefix + [result, result, history]
        XCTAssertEqual(Array(VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: complete).dropLast()), complete)
    }

    func testProtocolTurnIsCountedBeforeBudgetingAndCannotBeSilentlyDropped() throws {
        let original = [
            DevelopmentMessage(role: "system", content: "Retain this exact system boundary."),
            DevelopmentMessage(role: "user", content: "Retain every user requirement."),
            compacted("{\"ok\":true,\"output\":\"" + String(repeating: "source ", count: 250))
        ]
        let adapted = VyronOllamaDevelopmentContinuation.appendingIfNeeded(to: original)
        let originalBytes = try JSONEncoder().encode(original).count
        let adaptedBytes = try JSONEncoder().encode(adapted).count
        XCTAssertGreaterThan(adaptedBytes, originalBytes)
        XCTAssertEqual(try VyronDevelopmentRequestBudget.byteBoundedMessages(
            adapted, maximumMessageBytes: adaptedBytes
        ), adapted)
        XCTAssertThrowsError(try VyronDevelopmentRequestBudget.byteBoundedMessages(
            adapted, maximumMessageBytes: originalBytes
        )) { XCTAssertEqual($0 as? DevelopmentAgentError, .contextBudget) }
        XCTAssertEqual(Array(adapted.dropLast()), original)
    }

    private func compacted(_ source: String) -> DevelopmentMessage {
        VyronDevelopmentExchangeCompactor.compact(DevelopmentExchange(messages: [
            DevelopmentMessage(role: "tool", content: source, toolName: "read_file")
        ])).messages[0]
    }
}
