import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

final class VyronDevelopmentRunControlTests: XCTestCase {
    func testCallIDsAndJSONFieldOrderDoNotCreateProgress() throws {
        let first = DevelopmentToolCall(
            name: "read_file",
            arguments: ["path": .string("README.md"), "limit": .number(20)],
            id: "first"
        )
        let repeated = DevelopmentToolCall(
            name: "read_file",
            arguments: ["limit": .number(20), "path": .string("README.md")],
            id: "different-id"
        )
        XCTAssertEqual(
            try VyronDevelopmentRunControl.callKey(first),
            try VyronDevelopmentRunControl.callKey(repeated)
        )
        var control = VyronDevelopmentRunControl()
        try control.observe(first, response: #"{"ok":true,"output":"Project guidance","truncated":false}"#)
        control.finishRound()
        let version = control.progressVersion

        try control.observe(repeated, response: #"{"truncated":false,"output":"Project guidance","ok":true}"#)
        control.finishRound()

        XCTAssertEqual(control.progressVersion, version)
        XCTAssertEqual(control.stagnantRounds, 1)
        XCTAssertTrue(control.shouldReplan)
    }

    func testFailedAndUnchangedOutcomesNeverCountAsProgress() throws {
        let call = DevelopmentToolCall(name: "write_file", arguments: ["path": .string("Feature.swift")])
        let responses = [
            #"{"ok":false,"output":"The requested action was refused."}"#,
            #"{"ok":false,"output":"A different unsuccessful result."}"#,
            #"{"ok":true,"output":"Already matches Feature.swift; no file was rewritten."}"#,
            #"{"ok":true,"output":"The replacement is unchanged; no file was modified."}"#,
            #"{"ok":true,"output":"Previously attempted (succeeded); this action was not executed again."}"#
        ]
        var control = VyronDevelopmentRunControl()

        for response in responses {
            try control.observe(call, response: response)
            control.finishRound()
        }

        XCTAssertEqual(control.progressVersion, 0)
        XCTAssertEqual(control.stagnantRounds, responses.count)
        XCTAssertEqual(control.stalledTools, ["write_file"])
        XCTAssertTrue(control.shouldStop)
    }

    func testPlanAndResumeAcknowledgmentsCannotRenewWorkByThemselves() throws {
        var control = VyronDevelopmentRunControl()

        for tool in [VyronDevelopmentPlanTool.name, VyronDevelopmentResumeTool.name] {
            try control.observe(
                DevelopmentToolCall(name: tool, arguments: [:]),
                response: #"{"ok":true,"output":"Saved checkpoint"}"#
            )
            control.finishRound()
        }

        XCTAssertEqual(control.progressVersion, 0)
        XCTAssertEqual(control.stagnantRounds, 2)
        XCTAssertEqual(control.stalledTools, [VyronDevelopmentPlanTool.name, VyronDevelopmentResumeTool.name])
    }

    func testVaryingListLimitsWithoutNewResultsDoesNotAdvanceProgress() throws {
        var control = VyronDevelopmentRunControl()
        let response = #"{"ok":true,"output":"README.md (32 bytes)"}"#

        for limit in 1...4 {
            try control.observe(
                DevelopmentToolCall(name: "list_files", arguments: ["limit": .number(Double(limit))]),
                response: response
            )
            control.finishRound()
        }

        XCTAssertEqual(control.progressVersion, 1)
        XCTAssertEqual(control.stagnantRounds, 3)
        XCTAssertTrue(control.shouldStop)
        XCTAssertEqual(control.stalledTools, ["list_files"])
    }

    func testEmptyListingCursorMetadataCannotRenewProgress() throws {
        var control = VyronDevelopmentRunControl()

        for offset in 0...3 {
            try control.observe(
                DevelopmentToolCall(name: "list_files", arguments: ["offset": .number(Double(offset))]),
                response: try listingResponse(
                    offset: offset, paths: [], summary: "No matching paths at offset \(offset)."
                )
            )
            control.finishRound()
        }

        XCTAssertEqual(control.progressVersion, 1, "Cursor metadata is not new file evidence")
        XCTAssertEqual(control.stagnantRounds, 3)
        XCTAssertTrue(control.shouldStop)
        XCTAssertEqual(control.stalledTools, ["list_files"])
    }

    func testOnlyNewListingFilesResetStagnationAcrossCursorAndQueryChanges() throws {
        var control = VyronDevelopmentRunControl()
        let paths = ["examples/demo.py", "examples/demo.py", "eval/score.py", "eval/score.py"]

        for (offset, path) in paths.enumerated() {
            try control.observe(
                DevelopmentToolCall(name: "list_files", arguments: [
                    "offset": .number(Double(offset)), "query": .string("query-\(offset)")
                ]),
                response: try listingResponse(
                    offset: offset, paths: [path], summary: "Discovery page \(offset)."
                )
            )
            control.finishRound()
            if offset == 1 {
                XCTAssertEqual(control.progressVersion, 1)
                XCTAssertEqual(control.stagnantRounds, 1)
                XCTAssertTrue(control.shouldReplan)
            }
            if offset == 2 {
                XCTAssertEqual(control.progressVersion, 2)
                XCTAssertEqual(control.stagnantRounds, 0, "A newly discovered file is real progress")
                XCTAssertTrue(control.stalledTools.isEmpty)
            }
        }

        XCTAssertEqual(control.progressVersion, 2)
        XCTAssertEqual(control.stagnantRounds, 1, "The repeated file must not become progress at another cursor")
        XCTAssertTrue(control.shouldReplan)
        XCTAssertFalse(control.shouldStop)
    }

    func testLegacyOutputOnlyListingsStillRecognizeNewFileEvidence() throws {
        var control = VyronDevelopmentRunControl()
        let responses = [
            #"{"ok":true,"output":"README.md (32 bytes)"}"#,
            #"{"ok":true,"output":"README.md (32 bytes)"}"#,
            #"{"ok":true,"output":"README.md (32 bytes)\nFeature.swift (64 bytes)"}"#
        ]
        for (index, response) in responses.enumerated() {
            try control.observe(
                DevelopmentToolCall(name: "list_files", arguments: ["limit": .number(Double(index + 1))]),
                response: response
            )
            control.finishRound()
        }

        XCTAssertEqual(control.progressVersion, 2)
        XCTAssertEqual(control.stagnantRounds, 0)
        XCTAssertFalse(control.shouldReplan)
        XCTAssertTrue(control.stalledTools.isEmpty)
    }

    func testVaryingSearchQueriesWithoutNewResultsDoesNotAdvanceProgress() throws {
        var control = VyronDevelopmentRunControl()
        let response = #"{"ok":true,"output":"README.md:1: Project guidance"}"#

        for query in ["Project", "guidance", "Project guidance"] {
            try control.observe(
                DevelopmentToolCall(name: "search", arguments: ["query": .string(query)]),
                response: response
            )
            control.finishRound()
        }

        XCTAssertEqual(control.progressVersion, 1)
        XCTAssertEqual(control.stagnantRounds, 2)
    }

    func testUsefulReadAdvancesAndThreeUnchangedRoundsStop() throws {
        let call = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("Feature.swift")])
        var control = VyronDevelopmentRunControl()
        try control.observe(call, response: #"{"ok":true,"output":"let value = 1"}"#)
        control.finishRound()
        XCTAssertEqual(control.progressVersion, 1)

        try control.observe(call, response: #"{"ok":true,"output":"let value = 2"}"#)
        control.finishRound()
        XCTAssertEqual(control.progressVersion, 2)
        XCTAssertFalse(control.shouldReplan)

        for stagnantRound in 1...3 {
            try control.observe(call, response: #"{"ok":true,"output":"let value = 2"}"#)
            control.finishRound()
            XCTAssertEqual(control.progressVersion, 2)
            XCTAssertEqual(control.stagnantRounds, stagnantRound)
            XCTAssertEqual(control.shouldStop, stagnantRound == 3)
        }
    }

    func testUserGuidanceResetsStagnationWithoutRewindingProgress() throws {
        let call = DevelopmentToolCall(name: "read_file", arguments: ["path": .string("README.md")])
        let response = #"{"ok":true,"output":"Project guidance"}"#
        var control = VyronDevelopmentRunControl()
        try control.observe(call, response: response)
        control.finishRound()
        for _ in 0..<3 {
            try control.observe(call, response: response)
            control.finishRound()
        }
        XCTAssertTrue(control.shouldStop)
        let previousVersion = control.progressVersion

        control.appliedGuidance()
        control.finishRound()

        XCTAssertGreaterThan(control.progressVersion, previousVersion)
        XCTAssertEqual(control.stagnantRounds, 0)
        XCTAssertTrue(control.stalledTools.isEmpty)
        XCTAssertFalse(control.shouldStop)
        XCTAssertFalse(control.shouldReplan)

        try control.observe(call, response: response)
        control.finishRound()
        XCTAssertEqual(control.stagnantRounds, 0, "New user guidance permits reconsidering a previous result")
    }

    private func listingResponse(offset: Int, paths: [String], summary: String) throws -> String {
        let files = paths.map { path in
            DevelopmentJSONValue.object(["path": .string(path), "size": .number(64)])
        }
        let value = DevelopmentJSONValue.object([
            "ok": .bool(true), "files": .array(files), "output": .string(summary),
            "offset": .number(Double(offset)), "next_offset": .null,
            "total_matches": .number(Double(paths.count)), "scan_limited": .bool(false),
            "truncated": .bool(false)
        ])
        return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }
}
