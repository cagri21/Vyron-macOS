import Foundation
import XCTest
@testable import VyronCore

final class ProjectWorkspaceTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("vyron-workspace-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ text: String, path: String, root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    func testInventoryExcludesSecretsBuildProductsAndSymlinks() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        for path in ["Sources/App.swift", "README.md", "Package.swift", ".env", ".git/config", "node_modules/package/index.js", "build/result.swift", "secrets.json", "credentials.json", "private.pem", "GoogleService-Info.plist"] {
            try write("fixture", path: path, root: root)
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked.swift"), withDestinationURL: root.appendingPathComponent("Sources/App.swift"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("LinkedSources"), withDestinationURL: root.appendingPathComponent("Sources"))
        let workspace = try ProjectWorkspace(rootURL: root)
        let paths = try await workspace.files().map(\.path)
        XCTAssertEqual(Set(paths), ["Sources/App.swift", "README.md", "Package.swift"])
    }

    func testDirectReadsCannotEscapeProjectOrReadExcludedPaths() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("secret", path: "secrets.json", root: root)
        try write("source", path: "Sources/App.swift", root: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Alias.swift"), withDestinationURL: root.appendingPathComponent("Sources/App.swift"))
        let workspace = try ProjectWorkspace(rootURL: root)
        for path in ["../outside.swift", "/etc/hosts", "Sources/../Sources/App.swift", "secrets.json", ".env", "Alias.swift"] {
            do {
                _ = try await workspace.readFile(relativePath: path)
                XCTFail("Expected unsafe read rejection: \(path)")
            } catch {
                // Both policy and nonexistent-file errors are refusals, never contents.
            }
        }
        let source = try await workspace.readFile(relativePath: "Sources/App.swift")
        XCTAssertEqual(source, "source")
    }

    func testSourceReadIsBoundedAndKeepsValidUTF8() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("abc世界 and more", path: "App.swift", root: root)
        let workspace = try ProjectWorkspace(rootURL: root)
        let source = try await workspace.readFile(relativePath: "App.swift", maxBytes: 7)
        XCTAssertTrue(source.hasPrefix("abc世\n"))
        XCTAssertTrue(source.contains("Excerpt truncated at 7 bytes"))
        XCTAssertFalse(source.contains("�"))
    }

    func testBinarySourceIsRejectedAndSearchIsBounded() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("hello\nfind target\nTARGET again\n", path: "App.swift", root: root)
        try Data([0, 1, 2, 3]).write(to: root.appendingPathComponent("Binary.swift"))
        let workspace = try ProjectWorkspace(rootURL: root)
        do {
            _ = try await workspace.readFile(relativePath: "Binary.swift")
            XCTFail("Expected binary source rejection")
        } catch {
            XCTAssertTrue(error is LocalAIError)
        }
        let matches = try await workspace.search(query: "target", limit: 1)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.lineNumber, 2)
        XCTAssertEqual(matches.first?.path, "App.swift")
    }

    func testContextInventoryDoesNotReadFileContents() async throws {
        let root = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("PRIVATE_SOURCE_CONTENT", path: "App.swift", root: root)
        let workspace = try ProjectWorkspace(rootURL: root)
        let context = try await workspace.contextSummary()
        XCTAssertTrue(context.contains("App.swift"))
        XCTAssertFalse(context.contains("PRIVATE_SOURCE_CONTENT"))
        XCTAssertTrue(context.contains("untrusted task data"))
    }
}
