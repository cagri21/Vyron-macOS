import Foundation
import XCTest
import VyronAutomation

@MainActor
final class VyronAttachedApplicationTests: XCTestCase {
    func testExplicitBundleCanBeResolvedWithoutAddingItToTheInstalledCatalog() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("Selected Designer.app", isDirectory: true)
        let identifier = "com.example.vyron-test.selected-designer"
        try writeBundle(at: url, identifier: identifier)
        let controller = MacController()

        let resolved = try XCTUnwrap(controller.attachedApplication(at: url))
        XCTAssertEqual(resolved.bundleIdentifier, identifier)
        XCTAssertEqual(resolved.name, "Selected Designer")
        XCTAssertEqual(resolved.processIdentifier, 0)
        XCTAssertFalse(controller.availableApplications().contains { $0.id == identifier })
    }

    func testChangedBundleIdentifierIsReadAgainBeforeLaunch() async throws {
        let directory = try makeDirectory()
        let url = directory.appendingPathComponent("Selected Designer.app", isDirectory: true)
        let original = "com.example.vyron-test.original"
        let replacement = "com.example.vyron-test.replacement"
        try writeBundle(at: url, identifier: original)
        let controller = MacController()
        XCTAssertEqual(controller.attachedApplication(at: url)?.id, original)

        try writeBundle(at: url, identifier: replacement)
        XCTAssertEqual(controller.attachedApplication(at: url)?.id, replacement)
        do {
            _ = try await controller.launch(attachedApplicationAt: url, expectedApplicationID: original)
            XCTFail("The bundle identifier changed after the original target was resolved.")
        } catch MacControlError.applicationUnavailable {
            XCTAssertEqual(controller.attachedApplication(at: url)?.processIdentifier, 0)
        }
    }

    func testEmptyAndSymlinkedAppPathsAreRejected() async throws {
        let directory = try makeDirectory()
        let original = directory.appendingPathComponent("Selected Designer.app", isDirectory: true)
        let empty = directory.appendingPathComponent("Empty.app", isDirectory: true)
        let link = directory.appendingPathComponent("Linked.app", isDirectory: true)
        try writeBundle(at: original, identifier: "com.example.vyron-test.selected-designer")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let controller = MacController()

        XCTAssertNil(controller.attachedApplication(at: empty))
        XCTAssertNil(controller.attachedApplication(at: link))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func writeBundle(at url: URL, identifier: String) throws {
        let contents = url.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let metadata = [
            "CFBundleIdentifier": identifier,
            "CFBundlePackageType": "APPL",
            "CFBundleName": "Selected Designer"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
    }
}
