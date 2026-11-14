import Foundation
import XCTest
@testable import Vyron

final class VyronChangedProjectDestinationTests: XCTestCase {
    func testRootProjectOpensWithChangedXcodeGenSpec() throws {
        let root = try temporaryDirectory()
        let project = try makeProject("App.xcodeproj", in: root, buildSettings: "SDKROOT = iphoneos;")
        let specification = try makeFile("project.yml", in: root, contents: "name: App")

        let destination = try XCTUnwrap(VyronChangedProjectDestination.resolve(
            root: root, changedPaths: ["project.yml"]
        ))

        XCTAssertTrue(destination.opensInXcode)
        XCTAssertEqual(destination.projectURL.path, project.path)
        XCTAssertEqual(destination.changedFileURLs.map(\.path), [specification.path])
    }

    func testLinkedWorkspaceOpensForNestedIOSProject() throws {
        let root = try temporaryDirectory()
        _ = try makeProject("OtherApp.xcodeproj", in: root, buildSettings: "SDKROOT = iphoneos;")
        _ = try makeProject(
            "Clients/iOS/Mobile App.xcodeproj", in: root,
            buildSettings: "SUPPORTED_PLATFORMS = (iphoneos, iphonesimulator);"
        )
        let workspace = try makeFile("B-Mobile.xcworkspace/contents.xcworkspacedata", in: root, contents: """
            <?xml version="1.0" encoding="UTF-8"?>
            <Workspace version="1.0">
                <Group location="group:Clients">
                    <FileRef location="group:iOS/Mobile App.xcodeproj" />
                </Group>
            </Workspace>
            """).deletingLastPathComponent()
        _ = try makeFile("A-OtherApp.xcworkspace/contents.xcworkspacedata", in: root, contents: """
            <Workspace version="1.0"><FileRef location="group:OtherApp.xcodeproj" /></Workspace>
            """)
        let readme = try makeFile("README.md", in: root)
        let source = try makeFile("Clients/iOS/Sources/My View.swift", in: root)

        let destination = try XCTUnwrap(VyronChangedProjectDestination.resolve(
            root: root, changedPaths: ["README.md", "Clients/iOS/Sources/My View.swift"]
        ))

        XCTAssertTrue(destination.opensInXcode)
        XCTAssertEqual(destination.projectURL.path, workspace.path)
        XCTAssertEqual(destination.changedFileURLs.map(\.path), [readme.path, source.path])
    }

    func testNoIOSProjectOpensRootAndSkipsDependencyProjects() throws {
        let root = try temporaryDirectory()
        _ = try makeProject("Desktop.xcodeproj", in: root, buildSettings: "SDKROOT = macosx;")
        _ = try makeProject("Pods/Dependency.xcodeproj", in: root, buildSettings: "SDKROOT = iphoneos;")
        _ = try makeProject(".build-iOS/Dependency.xcodeproj", in: root, buildSettings: "SDKROOT = iphoneos;")
        _ = try makeFile("Pods/Dependency.swift", in: root)
        _ = try makeFile("Sources/Main.swift", in: root)

        let destination = try XCTUnwrap(VyronChangedProjectDestination.resolve(
            root: root, changedPaths: ["Pods/Dependency.swift", "Sources/Main.swift"]
        ))

        XCTAssertFalse(destination.opensInXcode)
        XCTAssertEqual(destination.projectURL.path, root.path)
        XCTAssertTrue(destination.changedFileURLs.isEmpty)
    }

    func testChangedPathsRejectMissingDirectoriesTraversalAndSymlinks() throws {
        let root = try temporaryDirectory()
        let outside = try temporaryDirectory()
        let externalSource = try makeFile("Outside.swift", in: outside)
        let file = try makeFile("Sources/Main.swift", in: root)
        _ = try makeProject("App.xcodeproj", in: root, buildSettings: "IPHONEOS_DEPLOYMENT_TARGET = 17.0;")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Sources/Linked.swift"), withDestinationURL: externalSource
        )
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Linked"), withDestinationURL: outside)

        let destination = try XCTUnwrap(VyronChangedProjectDestination.resolve(root: root, changedPaths: [
            "Sources/Main.swift", "Sources", "Sources/Main.swift", "Sources/Missing.swift", externalSource.path,
            "Sources/../Sources/Main.swift", "Sources/Linked.swift", "Linked/Outside.swift"
        ]))

        XCTAssertTrue(destination.opensInXcode)
        XCTAssertEqual(destination.changedFileURLs.map(\.path), [file.path])
    }

    func testDirectlyEditedXcodeProjectWinsOverSiblingProject() throws {
        let root = try temporaryDirectory()
        _ = try makeProject("A.xcodeproj", in: root, buildSettings: "SDKROOT = iphoneos;")
        let project = try makeProject("B.xcodeproj", in: root, buildSettings: "SDKROOT = iphoneos;")

        let destination = try XCTUnwrap(VyronChangedProjectDestination.resolve(
            root: root, changedPaths: ["B.xcodeproj/project.pbxproj"]
        ))

        XCTAssertEqual(destination.projectURL.path, project.path)
        XCTAssertEqual(destination.changedFileURLs.map(\.path), [project.appendingPathComponent("project.pbxproj").path])
    }

    func testMissingRootHasNoDestination() throws {
        let root = try temporaryDirectory()
        XCTAssertNil(VyronChangedProjectDestination.resolve(
            root: root.appendingPathComponent("Missing"), changedPaths: ["project.yml"]
        ))
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func makeProject(_ path: String, in root: URL, buildSettings: String) throws -> URL {
        try makeFile(path + "/project.pbxproj", in: root, contents: """
            // !$*UTF8*$!
            {
                objects = {
                    CONFIG = { isa = XCBuildConfiguration; buildSettings = { \(buildSettings) }; };
                };
            }
            """).deletingLastPathComponent()
    }

    private func makeFile(_ path: String, in root: URL, contents: String = "") throws -> URL {
        let file = root.appendingPathComponent(path, isDirectory: false)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        return file
    }
}
