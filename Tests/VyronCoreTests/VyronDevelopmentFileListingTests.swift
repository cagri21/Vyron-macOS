import Foundation
import XCTest
import VyronDevelopment

@MainActor
final class VyronDevelopmentFileListingTests: XCTestCase {
    func testDefaultDiscoveryPrioritizesSourcePathsInADocumentationHeavyProject() async throws {
        var files: [String: Data] = [
            "README.md": Data("Project documentation and Python examples.".utf8),
            "AGENTS.md": Data("Inspect source before proposing changes.".utf8),
            "examples/demo/cli_demo.py": Data("def run_demo(): pass\n".utf8),
            "eval/evaluate.py": Data("def evaluate(): pass\n".utf8)
        ]
        for index in 0..<400 {
            files["docs/topic-\(index).md"] = Data("Documentation \(index).".utf8)
        }
        let workspace = try project(files)

        let page = try await workspace.fileListing(VyronDevelopmentFileListingRequest(limit: 4))

        XCTAssertEqual(page.files.map(\.path), [
            "AGENTS.md", "README.md", "eval/evaluate.py", "examples/demo/cli_demo.py"
        ])
        XCTAssertEqual(page.coverage.offset, 0)
        XCTAssertEqual(page.coverage.nextOffset, 4)
        XCTAssertEqual(page.coverage.totalMatches, files.count)
        XCTAssertFalse(page.coverage.scanLimited)
        let changes = await workspace.changes()
        XCTAssertTrue(changes.isEmpty)
        do {
            _ = try await workspace.writeFile(path: "eval/evaluate.py", content: "unread replacement")
            XCTFail("Listing a source path must not grant editing permission")
        } catch is DevelopmentError {
            XCTAssertEqual(
                try Data(contentsOf: workspace.rootURL.appendingPathComponent("eval/evaluate.py")),
                files["eval/evaluate.py"]
            )
        }
    }

    func testPathFilterAndOffsetsDiscoverEveryMatchingFileExactlyOnce() async throws {
        let workspace = try project([
            "README.md": Data("mentions .py in its contents only".utf8),
            "docs/Python.md": Data("Python documentation".utf8),
            "eval/Generate.PY": Data("def generate(): pass\n".utf8),
            "examples/cli_demo.py": Data("def main(): pass\n".utf8),
            "examples/web_demo.py": Data("def launch(): pass\n".utf8)
        ])
        var paths: [String] = []
        var offset = 0
        repeat {
            let page = try await workspace.fileListing(VyronDevelopmentFileListingRequest(
                limit: 1, offset: offset, query: " .pY "
            ))
            XCTAssertEqual(page.coverage.offset, offset)
            XCTAssertEqual(page.coverage.totalMatches, 3)
            XCTAssertFalse(page.coverage.scanLimited)
            paths += page.files.map(\.path)
            guard let next = page.coverage.nextOffset else { break }
            XCTAssertGreaterThan(next, offset)
            offset = next
        } while true
        XCTAssertEqual(paths, ["eval/Generate.PY", "examples/cli_demo.py", "examples/web_demo.py"])
        XCTAssertEqual(Set(paths).count, 3)

        let named = try await workspace.fileListing(VyronDevelopmentFileListingRequest(query: "cli_demo.py"))
        XCTAssertEqual(named.files.map(\.path), ["examples/cli_demo.py"])
        let pastEnd = try await workspace.fileListing(VyronDevelopmentFileListingRequest(offset: 2_000, query: ".py"))
        XCTAssertTrue(pastEnd.files.isEmpty)
        XCTAssertNil(pastEnd.coverage.nextOffset)
        XCTAssertEqual(pastEnd.coverage.totalMatches, 3)
    }

    func testSecretGeneratedSymlinkAndOversizedPathsRemainExcluded() async throws {
        let workspace = try project([
            "Source.swift": Data("let visible = true\n".utf8),
            "secrets/private.py": Data("excluded synthetic fixture".utf8),
            ".build/Generated.py": Data("excluded generated fixture".utf8),
            ".env": Data("excluded synthetic environment fixture".utf8),
            "auth.json": Data("excluded synthetic authentication fixture".utf8),
            "Oversized.py": Data(repeating: 0x61, count: VyronDevelopmentFileReadBudget.maximumFileBytes + 1)
        ])
        let outside = try project(["Private.py": Data("outside synthetic fixture".utf8)])
        try FileManager.default.createSymbolicLink(
            at: workspace.rootURL.appendingPathComponent("Linked"),
            withDestinationURL: outside.rootURL
        )
        try FileManager.default.createSymbolicLink(
            at: workspace.rootURL.appendingPathComponent("External.py"),
            withDestinationURL: outside.rootURL.appendingPathComponent("Private.py")
        )

        let page = try await workspace.fileListing(VyronDevelopmentFileListingRequest())
        let filtered = try await workspace.fileListing(VyronDevelopmentFileListingRequest(query: ".py"))

        XCTAssertEqual(page.files.map(\.path), ["Source.swift"])
        XCTAssertTrue(filtered.files.isEmpty)
        XCTAssertEqual(filtered.coverage.totalMatches, 0)
    }

    func testFocusedDiscoveryCanPassTheUnfilteredInventoryCapWithoutClaimingExhaustiveCoverage() async throws {
        var files: [String: Data] = ["src/core.py": Data("def core(): pass\n".utf8)]
        for index in 0..<2_100 { files["docs/topic-\(index).md"] = Data() }
        let workspace = try project(files)

        let bounded = try await workspace.fileListing(VyronDevelopmentFileListingRequest(limit: 300))
        let source = try await workspace.fileListing(VyronDevelopmentFileListingRequest(query: ".py"))

        XCTAssertEqual(bounded.files.count, 300)
        XCTAssertEqual(bounded.coverage.totalMatches, 2_000)
        XCTAssertTrue(bounded.coverage.scanLimited)
        XCTAssertEqual(source.files.map(\.path), ["src/core.py"])
        XCTAssertEqual(source.coverage.totalMatches, 1)
        XCTAssertFalse(source.coverage.scanLimited)
    }

    func testInvalidRequestsFailAndCancellationStopsDiscovery() async throws {
        let workspace = try project(["Source.swift": Data("let value = 1\n".utf8)])
        let invalid = [
            VyronDevelopmentFileListingRequest(limit: 0),
            VyronDevelopmentFileListingRequest(limit: 301),
            VyronDevelopmentFileListingRequest(offset: -1),
            VyronDevelopmentFileListingRequest(offset: 2_001),
            VyronDevelopmentFileListingRequest(query: ""),
            VyronDevelopmentFileListingRequest(query: "  "),
            VyronDevelopmentFileListingRequest(query: "invalid\0query"),
            VyronDevelopmentFileListingRequest(query: String(repeating: "x", count: 501)),
            VyronDevelopmentFileListingRequest(query: String(repeating: "界", count: 167))
        ]
        for request in invalid {
            do {
                _ = try await workspace.fileListing(request)
                XCTFail("Invalid listing input must be rejected")
            } catch is DevelopmentError {}
        }
        let maximumQuery = try await workspace.fileListing(VyronDevelopmentFileListingRequest(
            query: String(repeating: "x", count: 500)
        ))
        XCTAssertTrue(maximumQuery.files.isEmpty)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await workspace.fileListing(VyronDevelopmentFileListingRequest())
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled discovery must not return a new page")
        } catch is CancellationError {}
    }

    private func project(_ files: [String: Data]) throws -> DevelopmentWorkspace {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronFileListing-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        for (path, data) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
        return try DevelopmentWorkspace(rootURL: root)
    }
}
