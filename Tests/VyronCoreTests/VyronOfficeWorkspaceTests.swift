import Foundation
import XCTest
import VyronDevelopment
@testable import VyronCore

@MainActor
final class VyronOfficeWorkspaceTests: XCTestCase {
    func testBinarySnapshotRejectsTraversalSecretsAndSymlinks() throws {
        let root = try directory()
        let workspace = VyronOfficeWorkspace(rootURL: root)
        let contents = Data([0x50, 0x4B, 0, 1, 2, 3])
        try contents.write(to: root.appendingPathComponent("source.xlsx"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.xlsx"), withDestinationURL: root.appendingPathComponent("source.xlsx")
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"), withDestinationURL: root
        )
        XCTAssertEqual(try workspace.snapshot(path: "source.xlsx"), contents)
        for path in ["../source.xlsx", "/source.xlsx", ".env.xlsx", "credentials/source.xlsx",
                     "link.xlsx", "linked/source.xlsx", "source.xlsx/child"] {
            XCTAssertThrowsError(try workspace.snapshot(path: path), path)
        }
    }

    func testExclusiveFilePublicationPreservesExistingOutputsAndInput() throws {
        let root = try directory()
        let workspace = VyronOfficeWorkspace(rootURL: root)
        let original = Data("keep".utf8)
        try original.write(to: root.appendingPathComponent("original.docx"))
        let artifact = VyronOfficeArtifact(name: "document.pdf", data: Data("%PDF-fixture".utf8))
        let publication = VyronOfficePublication(path: "result.pdf", artifacts: [artifact], isDirectory: false)
        XCTAssertEqual(try workspace.publish(publication), ["result.pdf"])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("result.pdf")), artifact.data)
        XCTAssertThrowsError(try workspace.publish(publication))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("original.docx")), original)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains {
            $0.hasPrefix(".vyron-office-")
        })
    }

    func testPublishedPreviewDirectoryRetainsAllImagesAndCannotBeReplaced() throws {
        let root = try directory()
        let workspace = VyronOfficeWorkspace(rootURL: root)
        let images = [
            VyronOfficeArtifact(name: "page-0001.png", data: Data([1, 2, 3])),
            VyronOfficeArtifact(name: "page-0002.png", data: Data([4, 5, 6]))
        ]
        let publication = VyronOfficePublication(path: "previews", artifacts: images, isDirectory: true)
        XCTAssertEqual(try workspace.publish(publication), ["previews/page-0001.png", "previews/page-0002.png"])
        for image in images {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("previews/" + image.name)), image.data)
        }
        XCTAssertThrowsError(try workspace.publish(publication))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["previews"])
    }

    func testOutputSymlinkAndInvalidEngineNamesNeverEscapeProject() throws {
        let root = try directory()
        let outside = try directory()
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("escape"), withDestinationURL: outside)
        let workspace = VyronOfficeWorkspace(rootURL: root)
        let artifact = VyronOfficeArtifact(name: "document.pdf", data: Data("PDF".utf8))
        XCTAssertThrowsError(try workspace.publish(VyronOfficePublication(
            path: "escape/result.pdf", artifacts: [artifact], isDirectory: false
        )))
        XCTAssertThrowsError(try workspace.publish(VyronOfficePublication(
            path: "previews", artifacts: [VyronOfficeArtifact(name: "../outside.png", data: Data([1]))], isDirectory: true
        )))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testSelectedPythonVenvSymlinkKeepsItsInvocationPath() throws {
        let root = try directory()
        let binary = root.appendingPathComponent("python3")
        try FileManager.default.createSymbolicLink(at: binary, withDestinationURL: URL(fileURLWithPath: "/usr/bin/python3"))
        let resolved = try VyronOfficeConfiguration(pythonExecutable: binary.path).resolvedExecutable()
        XCTAssertEqual(resolved, binary)
        XCTAssertNotEqual(resolved, binary.resolvingSymlinksInPath())
        XCTAssertThrowsError(try VyronOfficeConfiguration(pythonExecutable: "python3").resolvedExecutable())
        XCTAssertThrowsError(try VyronOfficeConfiguration(pythonExecutable: "/bin/sh").resolvedExecutable())
    }

    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronOfficeTests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: root) }
        return root
    }
}
