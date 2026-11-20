import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronDevelopmentFilePageTests: XCTestCase {
    func testUTF8PagesReachTheTailWithoutGrantingPartialOverwritePermission() async throws {
        let text = String(repeating: "İncele 検証 😀\n", count: 3_000) + "TAIL_REQUIREMENT\n"
        let workspace = try workspace(text)
        var offset = 0
        var restored = ""
        repeat {
            let page = try await workspace.readFilePage(
                VyronDevelopmentFileReadRequest(path: "Source.swift", offset: offset),
                budget: VyronDevelopmentFileReadBudget(maximumTextBytes: 1_000, maximumEncodedTextBytes: 1_500)
            )
            XCTAssertEqual(page.coverage.offset, offset)
            XCTAssertEqual(page.coverage.bytes, page.text.utf8.count)
            XCTAssertFalse(page.coverage.isWholeFile)
            restored += page.text
            guard let next = page.coverage.nextOffset else { break }
            guard next > offset else { return XCTFail("File paging did not advance") }
            offset = next
        } while true
        XCTAssertEqual(Data(restored.utf8), Data(text.utf8))
        do {
            _ = try await workspace.writeFile(path: "Source.swift", content: "discarded unseen content")
            XCTFail("Paged excerpts must not grant whole-file replacement permission")
        } catch is DevelopmentError {
            XCTAssertEqual(try String(contentsOf: workspace.rootURL.appendingPathComponent("Source.swift"),
                encoding: .utf8), text)
        }
    }

    func testEscapingBudgetIsAppliedBeforeGrantingEditingPermission() async throws {
        let text = String(repeating: "\u{0001}", count: 1_200)
        let workspace = try workspace(text)
        let page = try await workspace.readFilePage(
            VyronDevelopmentFileReadRequest(path: "Source.swift"),
            budget: VyronDevelopmentFileReadBudget(maximumTextBytes: 2_000, maximumEncodedTextBytes: 3_088)
        )
        XCTAssertFalse(page.coverage.isWholeFile)
        XCTAssertNotNil(page.coverage.nextOffset)
        XCTAssertLessThan(page.coverage.bytes, text.utf8.count)
        XCTAssertLessThanOrEqual(
            try VyronDevelopmentFileToolResponse.encode(page).utf8.count
                + VyronDevelopmentRunControl.readFeedbackReserveBytes,
            VyronDevelopmentRunLimits.toolOutputBytes
        )
        do {
            _ = try await workspace.writeFile(path: "Source.swift", content: "unsafe replacement")
            XCTFail("An encoded excerpt must not authorize replacing the omitted source")
        } catch is DevelopmentError {
            XCTAssertEqual(try Data(contentsOf: workspace.rootURL.appendingPathComponent("Source.swift")),
                Data(text.utf8))
        }
    }

    func testInvalidOffsetsSecretsAndSymlinksStayOutsidePageAccess() async throws {
        let workspace = try workspace("🙂\nlet value = 1\n")
        for offset in [-1, 1, 100_000] {
            do {
                _ = try await workspace.readFilePage(VyronDevelopmentFileReadRequest(
                    path: "Source.swift", offset: offset
                ))
                XCTFail("Invalid or mid-scalar offsets must be rejected")
            } catch is DevelopmentError {}
        }
        try Data("synthetic excluded fixture".utf8).write(to: workspace.rootURL.appendingPathComponent(".env"))
        try FileManager.default.createSymbolicLink(
            at: workspace.rootURL.appendingPathComponent("Link.swift"),
            withDestinationURL: workspace.rootURL.appendingPathComponent("Source.swift")
        )
        for path in [".env", "../Source.swift", "Link.swift"] {
            do {
                _ = try await workspace.readFilePage(VyronDevelopmentFileReadRequest(path: path))
                XCTFail("Paged reads must preserve native path boundaries")
            } catch is DevelopmentError {}
        }
    }

    func testChangedFileClearsEarlierFullReadPermissionAndCancelledReadGrantsNothing() async throws {
        let workspace = try workspace("let original = 1\n")
        _ = try await workspace.readFilePage(VyronDevelopmentFileReadRequest(path: "Source.swift"))
        let changed = String(repeating: "let changed = 2\n", count: 200)
        try Data(changed.utf8).write(to: workspace.rootURL.appendingPathComponent("Source.swift"))
        _ = try await workspace.readFilePage(
            VyronDevelopmentFileReadRequest(path: "Source.swift"),
            budget: VyronDevelopmentFileReadBudget(maximumTextBytes: 40)
        )
        do {
            _ = try await workspace.writeFile(path: "Source.swift", content: "stale full replacement")
            XCTFail("Earlier full-read permission must not survive a file change")
        } catch is DevelopmentError {}
        await workspace.beginTaskReadScope()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await workspace.readFilePage(VyronDevelopmentFileReadRequest(path: "Source.swift"))
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled page read must stop")
        } catch is CancellationError {}
        do {
            _ = try await workspace.writeFile(path: "Source.swift", content: "cancelled read replacement")
            XCTFail("A cancelled read must not authorize edits")
        } catch is DevelopmentError {
            XCTAssertEqual(try Data(contentsOf: workspace.rootURL.appendingPathComponent("Source.swift")),
                Data(changed.utf8))
        }
    }

    private func workspace(_ text: String) throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("VyronFilePage-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        try Data(text.utf8).write(to: root.appendingPathComponent("Source.swift"))
        return try DevelopmentWorkspace(rootURL: root)
    }
}
