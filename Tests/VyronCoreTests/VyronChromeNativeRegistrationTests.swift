import Foundation
import XCTest
@testable import VyronAutomation

final class VyronChromeNativeRegistrationTests: XCTestCase {
    func testRegistrationWritesIdenticalPrivateRecordWithOwnerOnlyPermissions() throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let app = try makeApp(fixture)
        try register(app, home: fixture)

        let record = privateRecord(in: fixture)
        XCTAssertEqual(try Data(contentsOf: record), try Data(contentsOf: chromeManifest(in: fixture)))
        let recordAttributes = try FileManager.default.attributesOfItem(atPath: record.path)
        XCTAssertEqual((recordAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let directoryAttributes = try FileManager.default.attributesOfItem(
            atPath: record.deletingLastPathComponent().path
        )
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    func testNativeOriginUsesPrivateRecordWhenChromeManifestDirectoryIsUnavailable() throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let app = try makeApp(fixture)
        try register(app, home: fixture)

        try FileManager.default.moveItem(
            at: chromeManifest(in: fixture).deletingLastPathComponent(),
            to: fixture.appendingPathComponent("unavailable-native-messaging-hosts")
        )
        XCTAssertEqual(try validateOrigin(for: app, home: fixture), extensionID)
    }

    func testNativeOriginRejectsAnUnsafePrivateRecordWhenChromeManifestIsValid() throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let app = try makeApp(fixture)
        try register(app, home: fixture)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: privateRecord(in: fixture).path)
        XCTAssertThrowsError(try validateOrigin(for: app, home: fixture)) { error in
            XCTAssertEqual(error as? VyronChromeBridgeError, .invalidPath)
        }
    }

    func testNativeOriginRejectsAnExtensionAuthorizedOnlyByChromeManifest() throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let app = try makeApp(fixture)
        try register(app, home: fixture)

        let manifest = chromeManifest(in: fixture)
        let staleRegistration = try Data(contentsOf: manifest)
        try VyronChromeNativeRegistration.register(
            extensionID: String(repeating: "b", count: 32), appURL: app, home: fixture
        )
        try staleRegistration.write(to: manifest)
        XCTAssertThrowsError(try validateOrigin(for: app, home: fixture)) { error in
            XCTAssertEqual(error as? VyronChromeBridgeError, .invalidOrigin)
        }
    }

    func testNativeOriginFallsBackWhenThePrivateRecordIsMissing() throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let app = try makeApp(fixture)
        try register(app, home: fixture)

        try FileManager.default.removeItem(at: privateRecord(in: fixture))
        XCTAssertEqual(try validateOrigin(for: app, home: fixture), extensionID)
    }

    func testExecutableDirectoryCannotBeRegistered() throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let app = fixture.appendingPathComponent("Vyron.app")
        let host = app.appendingPathComponent("Contents/MacOS/VyronChromeHost")
        try FileManager.default.createDirectory(
            at: host, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        XCTAssertThrowsError(try register(app, home: fixture))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.appendingPathComponent("Library").path))
    }

    func testExecutableSymlinkCannotBeRegistered() throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let app = try makeApp(fixture)
        let host = app.appendingPathComponent("Contents/MacOS/VyronChromeHost")
        let other = fixture.appendingPathComponent("other")
        try FileManager.default.moveItem(at: host, to: other)
        try FileManager.default.createSymbolicLink(at: host, withDestinationURL: other)
        XCTAssertThrowsError(try register(app, home: fixture))
    }

    func testGroupWritableExecutableCannotBeRegistered() throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let app = try makeApp(fixture)
        let host = app.appendingPathComponent("Contents/MacOS/VyronChromeHost")
        try FileManager.default.setAttributes([.posixPermissions: 0o770], ofItemAtPath: host.path)
        XCTAssertThrowsError(try register(app, home: fixture))
    }

    func testManifestSymlinkCannotReplaceUnrelatedFile() throws {
        let fixture = try makeFixture()
        defer { removeFixture(fixture) }
        let app = try makeApp(fixture)
        let directory = fixture.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        _ = try VyronChromeBridgeDirectory.open(directory, create: true, privateDirectory: false)
        let target = fixture.appendingPathComponent("unrelated.json")
        let before = Data("preserve".utf8)
        try before.write(to: target)
        try FileManager.default.createSymbolicLink(
            at: directory.appendingPathComponent("ai.vyron.chrome.json"), withDestinationURL: target
        )
        XCTAssertThrowsError(try register(app, home: fixture))
        XCTAssertEqual(try Data(contentsOf: target), before)
    }

    private let extensionID = String(repeating: "a", count: 32)

    private func register(_ app: URL, home: URL) throws {
        try VyronChromeNativeRegistration.register(extensionID: extensionID, appURL: app, home: home)
    }

    private func validateOrigin(for app: URL, home: URL) throws -> String {
        try VyronChromeNativeOrigin.validate(
            origin: "chrome-extension://\(extensionID)/",
            executable: app.appendingPathComponent("Contents/MacOS/VyronChromeHost").path,
            home: home
        )
    }

    private func chromeManifest(in home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts/ai.vyron.chrome.json")
    }

    private func privateRecord(in home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/VyronAI/ChromeBridge/registration.json")
    }

    private func makeApp(_ fixture: URL) throws -> URL {
        let app = fixture.appendingPathComponent("Vyron.app")
        let directory = try VyronChromeBridgeDirectory.open(
            app.appendingPathComponent("Contents/MacOS"), create: true, privateDirectory: false
        )
        try directory.write("VyronChromeHost", data: Data("synthetic executable".utf8))
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: app.appendingPathComponent("Contents/MacOS/VyronChromeHost").path
        )
        return app
    }

    private func makeFixture() throws -> URL {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/chrome-registration-tests/" + UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        return directory
    }

    private func removeFixture(_ fixture: URL) {
        do { try FileManager.default.removeItem(at: fixture) }
        catch { XCTFail("Registration fixture cleanup failed: \(error)") }
    }
}
