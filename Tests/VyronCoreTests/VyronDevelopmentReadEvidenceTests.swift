import Foundation
import XCTest
@testable import VyronCore

final class VyronDevelopmentReadEvidenceTests: XCTestCase {
    func testUnchangedReadKeepsContentAndAddsFeedbackWithoutCreatingProgress() throws {
        var control = VyronDevelopmentRunControl()
        let call = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Source.swift")])
        let response = #"{"ok":true,"output":"let value = 1","truncated":false}"#
        try control.observe(call, response: response)
        control.finishRound()
        let version = control.progressVersion
        try control.observe(call, response: response)
        let feedback = try object(control.readFeedback(response))
        XCTAssertEqual(feedback["output"] as? String, "let value = 1")
        XCTAssertEqual(feedback["unchanged_read"] as? Bool, true)
        XCTAssertTrue((feedback["read_guidance"] as? String)?.contains("conclude") == true)
        control.finishRound()
        XCTAssertEqual(control.progressVersion, version)
        XCTAssertEqual(control.stagnantRounds, 1)
        let ledger = try XCTUnwrap(control.readEvidenceGuidance())
        XCTAssertTrue(ledger.contains("Source.swift"))
        XCTAssertTrue(ledger.contains("contentHash"))
        XCTAssertFalse(ledger.contains("let value = 1"))
        XCTAssertTrue(control.partialReadScope?.contains("Source.swift") == true)
    }

    func testChangedContentAndNewUserGuidancePermitFreshReads() throws {
        var control = VyronDevelopmentRunControl()
        let call = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Source.swift")])
        for value in [1, 2] {
            let response = "{\"ok\":true,\"output\":\"let value = \(value)\"}"
            try control.observe(call, response: response)
            XCTAssertEqual(try control.readFeedback(response), response)
            control.finishRound()
        }
        XCTAssertEqual(control.progressVersion, 2)
        control.appliedGuidance()
        let response = #"{"ok":true,"output":"let value = 2"}"#
        try control.observe(call, response: response)
        XCTAssertEqual(try control.readFeedback(response), response)
        control.finishRound()
        XCTAssertEqual(control.stagnantRounds, 0)
    }

    func testRepeatedTaskPagesDoNotRenewProgress() throws {
        var document = try VyronDevelopmentTaskDocument(String(repeating: "x", count: 20_000))
        var control = VyronDevelopmentRunControl()
        let call = DevelopmentToolCall(name: "read_task", arguments: ["page": .number(0)])
        try control.observe(call, response: document.response(to: call))
        control.finishRound()
        let version = control.progressVersion
        for _ in 0..<VyronDevelopmentRunLimits.stagnantRounds {
            try control.observe(call, response: document.response(to: call))
            control.finishRound()
        }
        XCTAssertEqual(control.progressVersion, version)
        XCTAssertTrue(control.shouldStop)
    }

    func testEquivalentZeroOffsetsDoNotCreateProgressAndNewRangesDo() throws {
        var control = VyronDevelopmentRunControl()
        let implicit = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Source.swift")])
        let explicit = DevelopmentToolCall(name: "read_file", arguments: [
            "path": .string("Source.swift"), "offset": .number(0)
        ])
        let response = #"{"ok":true,"output":"same","offset":0,"bytes_read":4,"total_bytes":8,"truncated":true}"#
        try control.observe(implicit, response: response)
        control.finishRound()
        let version = control.progressVersion
        try control.observe(explicit, response: response)
        control.finishRound()
        XCTAssertEqual(control.progressVersion, version)
        try control.observe(DevelopmentToolCall(name: "read_file", arguments: [
            "path": .string("Source.swift"), "offset": .number(4)
        ]), response: #"{"ok":true,"output":"same","offset":4,"bytes_read":4,"total_bytes":8,"truncated":true}"#)
        control.finishRound()
        XCTAssertGreaterThan(control.progressVersion, version)
        let ledger = try XCTUnwrap(control.readEvidenceGuidance())
        XCTAssertTrue(ledger.contains("coverage"))
        control.beginReadScope()
        XCTAssertNil(try control.readEvidenceGuidance())
        XCTAssertNil(control.partialReadScope)
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
}
