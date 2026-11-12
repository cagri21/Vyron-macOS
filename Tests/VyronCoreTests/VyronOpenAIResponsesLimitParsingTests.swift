import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronOpenAIResponsesLimitParsingTests: XCTestCase {
    func testOnlyConfirmedOutputExhaustionUsesTheTypedLimitFailure() throws {
        let partial = VyronResponsesTestSupport.toolOutput("must-not-execute", name: "write_file")
        let data = try JSONSerialization.data(withJSONObject: [
            "status": "incomplete", "output": [partial],
            "incomplete_details": ["reason": "max_output_tokens"]
        ])
        let document = try JSONDecoder().decode(VyronOpenAIResponsesDocument.self, from: data)

        XCTAssertThrowsError(try document.completedOutput()) {
            XCTAssertEqual($0 as? ModelProviderError, .outputLimitReached)
        }
    }

    func testUnknownReasonsAndServerErrorsAreNeverClassifiedAsOutputExhaustion() throws {
        let details: [Any] = [
            NSNull(), ["reason": "content_filter"], ["reason": "unexpected"],
            ["reason": 42], "max_output_tokens"
        ]
        for detail in details {
            let data = try JSONSerialization.data(withJSONObject: [
                "status": "incomplete", "output": [], "incomplete_details": detail
            ])
            let document = try JSONDecoder().decode(VyronOpenAIResponsesDocument.self, from: data)
            XCTAssertThrowsError(try document.completedOutput()) {
                guard case .invalidResponse = $0 as? ModelProviderError else {
                    return XCTFail("Unexpected recoverable failure: \($0)")
                }
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "status": "incomplete", "output": [], "error": ["code": "server_error"],
            "incomplete_details": ["reason": "max_output_tokens"]
        ])
        let document = try JSONDecoder().decode(VyronOpenAIResponsesDocument.self, from: data)
        XCTAssertThrowsError(try document.completedOutput()) {
            guard case .invalidResponse = $0 as? ModelProviderError else {
                return XCTFail("A server failure must not enter output recovery")
            }
        }
    }

    func testIncompleteStreamsUseTheSameReasonAndRetainTheTerminalUsageEnvelope() throws {
        for reason in ["max_output_tokens", "content_filter", "unexpected"] {
            let terminal: [String: Any] = [
                "status": "incomplete", "output": [], "incomplete_details": ["reason": reason],
                "usage": ["input_tokens": 10, "output_tokens": 512]
            ]
            let event = try VyronResponsesTestSupport.json([
                "type": "response.incomplete", "response": terminal
            ])
            var parser = VyronOpenAIResponsesStream()
            XCTAssertThrowsError(try append("data: \(event)\n\n", to: &parser)) {
                if reason == "max_output_tokens" {
                    XCTAssertEqual($0 as? ModelProviderError, .outputLimitReached)
                } else {
                    guard case .invalidResponse = $0 as? ModelProviderError else {
                        return XCTFail("Unexpected recoverable stream failure: \($0)")
                    }
                }
            }
            XCTAssertFalse(parser.completed)
            XCTAssertTrue(parser.output.isEmpty)
            let envelope = try XCTUnwrap(parser.terminalResponse)
            XCTAssertTrue(String(decoding: try JSONEncoder().encode(envelope), as: UTF8.self).contains("usage"))
        }
    }

    private func append(_ event: String, to parser: inout VyronOpenAIResponsesStream) throws {
        for byte in event.utf8 { _ = try parser.append(byte) }
    }
}
