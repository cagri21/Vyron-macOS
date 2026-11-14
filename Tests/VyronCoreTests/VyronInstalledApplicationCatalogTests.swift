import Foundation
import XCTest
@testable import VyronAutomation

final class VyronInstalledApplicationCatalogTests: XCTestCase {
    private var workspace: URL?

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        workspace = directory
    }

    override func tearDownWithError() throws {
        if let workspace { try FileManager.default.removeItem(at: workspace) }
        workspace = nil
    }

    func testDiscoversClosedApplicationsAcrossRootsAndInsideUtilities() throws {
        let workspace = try XCTUnwrap(workspace)
        let system = workspace.appendingPathComponent("System/Applications", isDirectory: true)
        let shared = workspace.appendingPathComponent("Applications", isDirectory: true)
        let quickTime = try application(in: system, at: "QuickTime Player.app", identifier: "com.apple.QuickTimePlayerX")
        let utility = try application(in: system, at: "Utilities/Audio Tool.APP", identifier: "test.audio")
        let drawing = try application(in: shared, at: "Drawing Tool.app", identifier: "test.drawing")

        let result = VyronInstalledApplicationCatalog.applications(in: [system, shared])

        XCTAssertEqual(result.map(\.url), [quickTime, utility, drawing])
        XCTAssertEqual(result.map(\.application.name), ["QuickTime Player", "Audio Tool", "Drawing Tool"])
        XCTAssertEqual(result.map(\.application.processIdentifier), [0, 0, 0])
    }

    func testSkipsHelpersAndSymlinksAndRequiresApplicationMetadata() throws {
        let workspace = try XCTUnwrap(workspace)
        let applications = workspace.appendingPathComponent("Applications", isDirectory: true)
        let visible = try application(in: applications, at: "Visible.app", identifier: "test.visible")
        _ = try application(in: visible, at: "Contents/Helpers/Browser.app", identifier: "test.helper")
        _ = try application(in: applications, at: ".Hidden.app", identifier: "test.hidden")
        _ = try application(in: applications, at: "Framework.app", identifier: "test.invalid", packageType: "FMWK")
        let external = try application(in: workspace, at: "External/Other.app", identifier: "test.other")
        let externalAppLink = applications.appendingPathComponent("Linked.app", isDirectory: true)
        let externalFolderLink = applications.appendingPathComponent("External", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: externalAppLink, withDestinationURL: external)
        try FileManager.default.createSymbolicLink(at: externalFolderLink, withDestinationURL: external.deletingLastPathComponent())

        let result = VyronInstalledApplicationCatalog.applications(in: [applications, externalFolderLink])

        XCTAssertEqual(result.map(\.url), [visible])
        XCTAssertNil(VyronInstalledApplicationCatalog.application(at: externalAppLink))
    }

    func testDuplicateIdentifiersPreferEarlierDirectoryAndTopLevelBundle() throws {
        let workspace = try XCTUnwrap(workspace)
        let system = workspace.appendingPathComponent("System", isDirectory: true)
        let local = workspace.appendingPathComponent("Local", isDirectory: true)
        let primary = try application(in: system, at: "Original.app", identifier: "test.duplicate")
        _ = try application(in: system, at: "Copies/Earlier Name.app", identifier: "test.duplicate")
        _ = try application(in: local, at: "Copy.app", identifier: "test.duplicate")

        let result = VyronInstalledApplicationCatalog.applications(in: [system, local])

        XCTAssertEqual(result.map(\.url), [primary])
    }

    @MainActor
    func testControllerListsAndResolvesClosedAppsWhileLaunchRequiresReview() throws {
        let workspace = try XCTUnwrap(workspace)
        let playerID = "test.video-player"
        let designerID = "test.design-tool"
        let player = try application(in: workspace, at: "Video Player.app", identifier: playerID)
        let designer = try application(in: workspace, at: "Design Tool.app", identifier: designerID)
        let controller = MacController(applicationDirectories: [workspace])

        let available = controller.availableApplications()

        XCTAssertEqual(available.first { $0.id == playerID }?.processIdentifier, 0)
        XCTAssertEqual(available.first { $0.id == designerID }?.processIdentifier, 0)
        XCTAssertEqual(controller.installedCatalogApplication(for: playerID)?.url, player)
        XCTAssertEqual(controller.installedCatalogApplication(for: designerID)?.url, designer)
        guard case .review = AutomationPolicy.evaluate(kind: "launch", applicationID: playerID, goal: "Open Video Player")
        else { return XCTFail("Expected review before opening a newly discovered application.") }
    }

    @MainActor
    func testApprovedApplicationCannotSwitchToAnotherCopyAfterDiscovery() throws {
        let workspace = try XCTUnwrap(workspace)
        let firstRoot = workspace.appendingPathComponent("First", isDirectory: true)
        let secondRoot = workspace.appendingPathComponent("Second", isDirectory: true)
        let identifier = "test.selected-player"
        let original = try application(in: firstRoot, at: "Video Player.app", identifier: identifier)
        let replacement = try application(in: secondRoot, at: "Video Player.app", identifier: identifier)
        let controller = MacController(applicationDirectories: [firstRoot, secondRoot])
        let approved = try XCTUnwrap(controller.availableApplications().first { $0.id == identifier })
        XCTAssertEqual(approved.installationURL, original)
        XCTAssertEqual(controller.validatedInstallationURL(for: approved), original)

        try FileManager.default.removeItem(at: original)

        XCTAssertEqual(controller.installedCatalogApplication(for: identifier)?.url, replacement)
        XCTAssertNil(controller.validatedInstallationURL(for: approved))
    }

    private func application(
        in directory: URL,
        at relativePath: String,
        identifier: String,
        packageType: String = "APPL"
    ) throws -> URL {
        let url = directory.appendingPathComponent(relativePath, isDirectory: true)
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let metadata = ["CFBundleIdentifier": identifier, "CFBundlePackageType": packageType]
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        return url
    }
}
