import Foundation
import XCTest
import VyronAutomation
import VyronCore
@testable import Vyron

@MainActor
final class VyronMacWorkProjectTests: XCTestCase {
    func testProjectOpenUsesNativeXcodeWithOnlyTheValidatedWorkspacePath() async throws {
        let root = try temporaryDirectory()
        defer { remove(root) }
        let project = root.appendingPathComponent("Finator/Finator.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let controller = VyronMacWorkTestController()
        let xcodeID = VyronMacWorkApplicationIDs.xcode
        controller.catalog = [DesktopApplication(
            id: xcodeID, name: "Xcode", bundleIdentifier: xcodeID, processIdentifier: 50
        )]
        let session = VyronMacWorkSession(
            context: VyronMacWorkContext(goal: "Run Finator", projectRoot: root, allowsActions: true),
            dependencies: VyronMacWorkDependencies(controller: controller, validateCurrent: {}, review: { _ in false })
        )
        let result = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.openProject, arguments: ["path": .string("Finator/Finator.xcodeproj")]
        ))
        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(controller.openedProjects, [project])
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.path))
        XCTAssertTrue(result.text.contains("Inspect Xcode"))
    }

    func testRelativeProjectAndWorkspacePackagesAreAccepted() throws {
        let root = try temporaryDirectory()
        defer { remove(root) }
        for path in ["Finator.xcodeproj", "Workspace/Finator.xcworkspace"] {
            let project = root.appendingPathComponent(path, isDirectory: true)
            try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
            XCTAssertEqual(try VyronMacWorkProject.resolve(path: path, root: root), project)
        }
    }

    func testProjectSwitchUsesNewRootAndInvalidatesEarlierNativeSnapshots() async throws {
        let firstRoot = try temporaryDirectory()
        defer { remove(firstRoot) }
        let nextRoot = try temporaryDirectory()
        defer { remove(nextRoot) }
        for root in [firstRoot, nextRoot] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent("Finator.xcodeproj"), withIntermediateDirectories: true
            )
        }
        let controller = VyronMacWorkTestController()
        let xcodeID = VyronMacWorkApplicationIDs.xcode
        controller.catalog.append(DesktopApplication(
            id: xcodeID, name: "Xcode", bundleIdentifier: xcodeID, processIdentifier: 50
        ))
        let session = VyronMacWorkSession(
            context: VyronMacWorkContext(goal: "Run Finator", projectRoot: firstRoot, allowsActions: true),
            dependencies: VyronMacWorkDependencies(controller: controller, validateCurrent: {}, review: { _ in false })
        )
        let open = DevelopmentToolCall(
            name: VyronMacWorkTools.openProject, arguments: ["path": .string("Finator.xcodeproj")]
        )
        let first = try await session.execute(open)
        XCTAssertFalse(first.isError, first.text)
        _ = try await session.execute(DevelopmentToolCall(
            name: VyronMacWorkTools.inspect, arguments: ["application_id": .string(VyronMacWorkTestController.app.id)]
        ))
        XCTAssertFalse(session.snapshots.isEmpty)

        try session.updateProjectRoot(nextRoot)

        XCTAssertTrue(session.snapshots.isEmpty)
        let next = try await session.execute(open)
        XCTAssertFalse(next.isError, next.text)
        XCTAssertEqual(controller.openedProjects, [
            firstRoot.appendingPathComponent("Finator.xcodeproj"),
            nextRoot.appendingPathComponent("Finator.xcodeproj")
        ])
    }

    func testStaleResponseCannotUpdateItsProjectRoot() throws {
        let root = try temporaryDirectory()
        defer { remove(root) }
        let controller = VyronMacWorkTestController()
        let response = VyronMacWorkTestResponseState()
        let session = VyronMacWorkSession(
            context: VyronMacWorkContext(goal: "Run Finator", projectRoot: root, allowsActions: true),
            dependencies: VyronMacWorkDependencies(
                controller: controller, validateCurrent: response.validate, review: { _ in false }
            )
        )
        response.isCurrent = false
        XCTAssertThrowsError(try session.updateProjectRoot(root)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(session.currentProjectRoot, root)
    }

    func testAbsoluteTraversalMissingAndNonProjectPathsAreRefused() throws {
        let root = try temporaryDirectory()
        defer { remove(root) }
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Sources"), withIntermediateDirectories: true
        )
        for path in ["/Applications/Xcode.app", "../Other.xcodeproj", "~/Desktop/Finator.xcodeproj", "Sources",
                     "Missing.xcodeproj", "./Finator.xcodeproj", "Finator.xcodeproj/", "a//b.xcodeproj"] {
            XCTAssertThrowsError(try VyronMacWorkProject.resolve(path: path, root: root), path)
        }
        XCTAssertThrowsError(try VyronMacWorkProject.resolve(path: "Finator.xcodeproj", root: nil))
    }

    func testSymbolicLinksAtThePackageAndItsParentsAreRefused() throws {
        let root = try temporaryDirectory()
        defer { remove(root) }
        let outside = try temporaryDirectory()
        defer { remove(outside) }
        let package = outside.appendingPathComponent("Real.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked.xcodeproj"), withDestinationURL: package
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Linked"), withDestinationURL: outside
        )
        XCTAssertThrowsError(try VyronMacWorkProject.resolve(path: "Linked.xcodeproj", root: root))
        XCTAssertThrowsError(try VyronMacWorkProject.resolve(path: "Linked/Real.xcodeproj", root: root))
    }

    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.resolvingSymlinksInPath()
    }

    private func remove(_ directory: URL) {
        do { try FileManager.default.removeItem(at: directory) } catch { XCTFail(error.localizedDescription) }
    }
}
