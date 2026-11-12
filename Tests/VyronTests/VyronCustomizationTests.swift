import Foundation
import XCTest
@testable import Vyron
@testable import VyronCore

@MainActor
final class VyronCustomizationTests: XCTestCase {
    func testSkillsNavigationPreservesPluginSelectionUntilReturningToCatalog() {
        let presentation = VyronPluginsPresentation()
        let connectionID = UUID()
        presentation.select(connectionID)
        presentation.searchQuery = "design"
        presentation.showSkills()

        XCTAssertEqual(presentation.section, .skills)
        XCTAssertEqual(presentation.selectedConnectionID, connectionID)
        XCTAssertEqual(presentation.searchQuery, "design")

        presentation.select(connectionID)
        XCTAssertEqual(presentation.section, .plugins)
        presentation.showSkills()
        presentation.showAll()
        XCTAssertEqual(presentation.section, .plugins)
        XCTAssertNil(presentation.selectedConnectionID)
        XCTAssertEqual(presentation.searchQuery, "")
    }

    func testRefreshReadsSavedProfilesWithoutConnectingServices() throws {
        let directory = try makeDirectory()
        let store = MCPConnectionStore(fileURL: directory.appendingPathComponent("mcp-connections.json"))
        let original = MCPConnectionProfile(name: "Original", endpoint: "https://original.invalid/mcp")
        try store.save([original])
        let model = MCPConnectionsModel(store: store) { _, _ in
            XCTFail("Refreshing must never construct an MCP client.")
            throw URLError(.unsupportedURL)
        }
        let replacement = MCPConnectionProfile(name: "Replacement", endpoint: "https://replacement.invalid/mcp")
        try store.save([replacement])

        model.refreshProfiles()

        XCTAssertEqual(model.profiles, [replacement])
        XCTAssertEqual(model.connectedCount, 0)
        XCTAssertTrue(model.tools.isEmpty)
        XCTAssertNil(model.error)
    }

    func testRefreshPreservesProfilesOnUnreadableFileAndRecoversAfterRepair() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("mcp-connections.json")
        let store = MCPConnectionStore(fileURL: file)
        let profile = MCPConnectionProfile(name: "Keep me", endpoint: "https://keep.invalid/mcp")
        try store.save([profile])
        let model = MCPConnectionsModel(store: store)
        let damaged = Data("{ damaged file".utf8)
        try damaged.write(to: file)

        model.refreshProfiles()

        XCTAssertEqual(model.profiles, [profile])
        XCTAssertNotNil(model.error)
        XCTAssertEqual(try Data(contentsOf: file), damaged)

        try store.save([])
        model.refreshProfiles()
        XCTAssertTrue(model.profiles.isEmpty)
        XCTAssertNil(model.error)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronCustomizationTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }
}
