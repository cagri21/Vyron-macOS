import Foundation
import XCTest
@testable import VyronAutomation

final class VyronXcodeApplicationCatalogTests: XCTestCase {
    private var directory: URL?

    override func setUpWithError() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true
        )
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory {
            try FileManager.default.removeItem(at: directory)
        }
        directory = nil
    }

    func testKnownSimulatorToolsCanUseNativeLaunchPolicy() {
        for applicationID in VyronXcodeApplicationCatalog.applicationIDs {
            let decision = AutomationPolicy.evaluate(
                kind: "launch", applicationID: applicationID, goal: "Open Simulator"
            )
            guard case .automatic = decision else {
                XCTFail("Expected native launch support for \(applicationID)")
                continue
            }
        }
    }

    func testRegisteredApplicationKeepsItsExistingLocation() throws {
        let applicationID = VyronXcodeApplicationCatalog.simulatorID
        let registered = try application(at: "Standalone Simulator.app", identifier: applicationID)
        let resolved = VyronXcodeApplicationCatalog.applicationURL(
            for: applicationID, registeredURL: registered, xcodeURL: nil
        )
        XCTAssertEqual(resolved, registered)
    }

    func testUnregisteredSimulatorIsDiscoveredInsideLegacyXcodeLayout() throws {
        let xcode = try application(at: "Xcode.app", identifier: VyronXcodeApplicationCatalog.xcodeID)
        let applicationID = VyronXcodeApplicationCatalog.simulatorID
        let simulator = try application(
            at: "Xcode.app/Contents/Developer/Applications/Simulator.app", identifier: applicationID
        )
        let resolved = VyronXcodeApplicationCatalog.applicationURL(
            for: applicationID, registeredURL: nil, xcodeURL: xcode
        )
        XCTAssertEqual(resolved, simulator)
    }

    func testUnregisteredDeviceHubIsDiscoveredInsideCurrentXcodeLayout() throws {
        let xcode = try application(at: "Xcode.app", identifier: VyronXcodeApplicationCatalog.xcodeID)
        let applicationID = VyronXcodeApplicationCatalog.deviceHubID
        let deviceHub = try application(
            at: "Xcode.app/Contents/Applications/DeviceHub.app", identifier: applicationID
        )
        let resolved = VyronXcodeApplicationCatalog.applicationURL(
            for: applicationID, registeredURL: nil, xcodeURL: xcode
        )
        XCTAssertEqual(resolved, deviceHub)
    }

    func testNestedFallbackRequiresMatchingApplicationAndXcodeIdentities() throws {
        let xcode = try application(at: "Xcode.app", identifier: VyronXcodeApplicationCatalog.xcodeID)
        _ = try application(
            at: "Xcode.app/Contents/Applications/DeviceHub.app", identifier: "com.example.WrongApp"
        )
        XCTAssertNil(VyronXcodeApplicationCatalog.applicationURL(
            for: VyronXcodeApplicationCatalog.deviceHubID, registeredURL: nil, xcodeURL: xcode
        ))
        let otherApp = try application(at: "Other.app", identifier: "com.example.Other")
        _ = try application(
            at: "Other.app/Contents/Applications/DeviceHub.app", identifier: VyronXcodeApplicationCatalog.deviceHubID
        )
        XCTAssertNil(VyronXcodeApplicationCatalog.applicationURL(
            for: VyronXcodeApplicationCatalog.deviceHubID, registeredURL: nil, xcodeURL: otherApp
        ))
    }

    func testRegisteredIdentityMismatchAndUnknownNestedApplicationsAreRejected() throws {
        let otherApp = try application(at: "Other.app", identifier: "com.example.Other")
        XCTAssertNil(VyronXcodeApplicationCatalog.applicationURL(
            for: VyronXcodeApplicationCatalog.simulatorID, registeredURL: otherApp, xcodeURL: nil
        ))
        let xcode = try application(at: "Xcode.app", identifier: VyronXcodeApplicationCatalog.xcodeID)
        _ = try application(at: "Xcode.app/Contents/Applications/Unknown.app", identifier: "com.example.Unknown")
        XCTAssertNil(VyronXcodeApplicationCatalog.applicationURL(
            for: "com.example.Unknown", registeredURL: nil, xcodeURL: xcode
        ))
    }

    private func application(at relativePath: String, identifier: String) throws -> URL {
        let directory = try XCTUnwrap(directory)
        let applicationURL = directory.appendingPathComponent(relativePath, isDirectory: true)
        let contentsURL = applicationURL.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        let metadata = ["CFBundleIdentifier": identifier, "CFBundlePackageType": "APPL", "CFBundleName": "Test App"]
        let data = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try data.write(to: contentsURL.appendingPathComponent("Info.plist"))
        return applicationURL
    }
}
