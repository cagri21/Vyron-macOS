import Foundation
import XCTest
@testable import Vyron

final class VyronChromeHostRegistrationTests: XCTestCase {
    func testRegistrationUsesOnlyExplicitExtensionAndAbsoluteBundledHost() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try makeApp(in: directory)
        let extensionID = String(repeating: "a", count: 32)
        try VyronChromeHostRegistration.register(extensionID: extensionID, appURL: app, home: directory)
        let manifest = manifestURL(in: directory)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        XCTAssertEqual(json["name"] as? String, "ai.vyron.chrome")
        XCTAssertEqual(json["path"] as? String, app.appendingPathComponent("Contents/MacOS/VyronChromeHost").path)
        XCTAssertEqual(json["allowed_origins"] as? [String], ["chrome-extension://" + extensionID + "/"])
        let attributes = try FileManager.default.attributesOfItem(atPath: manifest.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testInvalidIdentityDoesNotOverwriteExistingManifest() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = try makeApp(in: directory)
        try VyronChromeHostRegistration.register(
            extensionID: String(repeating: "a", count: 32), appURL: app, home: directory
        )
        let before = try Data(contentsOf: manifestURL(in: directory))
        for invalid in ["*", String(repeating: "A", count: 32), String(repeating: "q", count: 32), "../host"] {
            XCTAssertThrowsError(try VyronChromeHostRegistration.register(
                extensionID: invalid, appURL: app, home: directory
            ))
        }
        XCTAssertEqual(try Data(contentsOf: manifestURL(in: directory)), before)
    }

    func testMissingHelperOrSymlinkCannotInstall() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let extensionID = String(repeating: "b", count: 32)
        XCTAssertThrowsError(try VyronChromeHostRegistration.register(
            extensionID: extensionID, appURL: directory.appendingPathComponent("Missing.app"), home: directory
        ))
        let app = try makeApp(in: directory)
        let other = directory.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("Library"), withDestinationURL: other
        )
        XCTAssertThrowsError(try VyronChromeHostRegistration.register(
            extensionID: extensionID, appURL: app, home: directory
        ))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: other.path).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeApp(in directory: URL) throws -> URL {
        let app = directory.appendingPathComponent("Vyron.app")
        let host = app.appendingPathComponent("Contents/MacOS/VyronChromeHost")
        try FileManager.default.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("synthetic executable".utf8).write(to: host)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: host.path)
        return app
    }

    private func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts/ai.vyron.chrome.json")
    }
}
