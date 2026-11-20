import Foundation
import XCTest
import VyronModelDomain
@testable import VyronCore

final class VyronDevelopmentTaskDocumentTests: XCTestCase {
    func testUnicodeAndEscapedTaskPagesReconstructEveryByteWithinTheToolBudget() throws {
        for original in [
            "BEGIN\n" + String(repeating: "İncele 検証 😀\n", count: 3_000) + "\nEND",
            "BEGIN" + String(repeating: "\"\\\u{0001}", count: 8_000) + "END"
        ] {
            var document = try VyronDevelopmentTaskDocument(original)
            XCTAssertTrue(document.isPaged)
            XCTAssertTrue(document.hasUnreadPages)
            XCTAssertLessThan(document.reference.utf8.count, 2_000)
            var reconstructed = ""
            var next = 0
            while document.hasUnreadPages {
                let response = try document.response(to: call(next))
                XCTAssertLessThanOrEqual(response.utf8.count, VyronDevelopmentRunLimits.toolOutputBytes)
                let fields = try object(response)
                reconstructed += try XCTUnwrap(fields["output"] as? String)
                XCTAssertEqual(fields["truncated"] as? Bool, false)
                next += 1
            }
            XCTAssertEqual(Data(reconstructed.utf8), Data(original.utf8))
            let repeated = try object(document.response(to: call(0)))
            XCTAssertEqual(repeated["already_read"] as? Bool, true)
            XCTAssertTrue(repeated["next_page"] is NSNull)
        }
    }

    func testShortTasksStayInlineAndInvalidPagesCannotAdvanceReadState() throws {
        let short = try VyronDevelopmentTaskDocument("Analyze this code")
        XCTAssertFalse(short.isPaged)
        XCTAssertFalse(short.hasUnreadPages)
        XCTAssertEqual(short.reference, "Analyze this code")
        var document = try VyronDevelopmentTaskDocument(String(repeating: "x", count: 20_000))
        for index in [-1.0, 0.5, 100_000.0] {
            XCTAssertThrowsError(try document.response(to: DevelopmentToolCall(
                name: "read_task", arguments: ["page": .number(index)]
            )))
        }
        XCTAssertTrue(document.hasUnreadPages)
        XCTAssertThrowsError(try document.response(to: DevelopmentToolCall(
            name: "read_task", arguments: ["page": .number(0), "path": .string(".env")]
        )))
    }

    func testCurrentTaskPageSurvivesForcedCompactionBeforeFirstInferenceDelivery() throws {
        let text = "CURRENT_REQUIREMENT" + String(repeating: " x", count: 1_000) + "END_REQUIREMENT"
        let call = DevelopmentToolCall(name: "read_task", arguments: ["page": .number(0)])
        let page = DevelopmentMessage(role: "tool", content: text, toolName: "read_task")
        let exchange = DevelopmentExchange(messages: [
            DevelopmentMessage(role: "assistant", toolCalls: [call]), page
        ])
        let messages = try VyronDevelopmentExchangeCompactor.messages(
            base: [DevelopmentMessage(role: "user", content: "Preserve every original requirement")],
            exchanges: [exchange], forceCompact: true,
            budget: VyronDevelopmentMessageBudget(workingBytes: 1_000, maximumBytes: 5_000)
        )
        XCTAssertEqual(messages.last, page)
        XCTAssertTrue(try XCTUnwrap(messages.last).content.hasSuffix("END_REQUIREMENT"))
    }

    private func call(_ page: Int) -> DevelopmentToolCall {
        DevelopmentToolCall(name: "read_task", arguments: ["page": .number(Double(page))])
    }

    private func object(_ value: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any])
    }
}
