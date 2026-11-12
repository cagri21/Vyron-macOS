import Foundation
import XCTest
@testable import VyronCore

final class SidebarOrganizationSourceFoldersTests: XCTestCase {
    func testLegacyAndUnregisteredProjectsDefaultToTheirOriginalCanonicalFolder() throws {
        var organization = SidebarOrganization()
        let project = "/Projects/Original"
        try organization.registerProject(path: project)
        var stored = try encodedObject(organization)
        stored.removeValue(forKey: "projectSources")

        let restored = try decode(stored)

        XCTAssertEqual(restored, organization)
        XCTAssertEqual(restored.projectSourceFolders(for: project), [project])
        XCTAssertEqual(restored.projectSourceFolders(for: "/Projects/Old/../Original"), [project])
        XCTAssertEqual(restored.projectSourceFolders(for: "/Missing/Unregistered"), ["/Missing/Unregistered"])
        XCTAssertFalse(restored.contains(.project("/Missing/Unregistered")))
    }

    func testProjectEditRoundTripsOrderedSourceReferencesSeparatelyFromProjectIdentity() throws {
        var organization = SidebarOrganization()
        let project = "/Projects/Identity"
        let sources = ["/Volumes/Offline/Server", "/Projects/Old/../Client"]
        try organization.updateProject(
            path: "/Projects/Old/../Identity",
            name: "  Combined Project  ",
            sourceFolders: sources
        )

        var restored = try decode(encodedObject(organization))

        XCTAssertEqual(restored, organization)
        XCTAssertEqual(restored.allProjects, [project])
        XCTAssertEqual(restored.projectDisplayName(for: project), "Combined Project")
        XCTAssertEqual(restored.projectSourceFolders(for: project), ["/Volumes/Offline/Server", "/Projects/Client"])
        XCTAssertFalse(restored.projectSourceFolders(for: project).contains(project))
        XCTAssertFalse(restored.contains(.project("/Projects/Client")))
        try restored.renameProject(path: project, name: "Renamed Label")
        XCTAssertEqual(restored.projectDisplayName(for: project), "Renamed Label")
        XCTAssertEqual(restored.projectSourceFolders(for: project), ["/Volumes/Offline/Server", "/Projects/Client"])
    }

    func testSourceFolderCanBeSharedByDistinctProjectIdentities() throws {
        var organization = SidebarOrganization()
        let shared = "/Projects/Shared"
        try organization.updateProject(path: "/Projects/First", name: "First", sourceFolders: [shared])
        try organization.updateProject(path: "/Projects/Second", name: "Second", sourceFolders: [shared])

        let restored = try decode(encodedObject(organization))

        XCTAssertEqual(restored.allProjects, ["/Projects/First", "/Projects/Second"])
        XCTAssertEqual(restored.projectSourceFolders(for: "/Projects/First"), [shared])
        XCTAssertEqual(restored.projectSourceFolders(for: "/Projects/Second"), [shared])
    }

    func testInvalidSourceFoldersAndNamesLeaveAllMetadataUnchanged() throws {
        var organization = SidebarOrganization()
        try organization.updateProject(path: "/Projects/Kept", name: "Kept", sourceFolders: ["/Sources/Kept"])
        let original = organization
        let invalidSources = [
            [],
            ["relative/path"],
            ["/Sources/Bad\nName"],
            ["/Sources/Bad\u{0}Name"],
            ["/Sources/Duplicate", "/Sources/Duplicate"],
            ["/Sources/Duplicate", "/Sources/Old/../Duplicate"],
            ["/" + String(repeating: "x", count: 4_096)],
            (0...VyronSidebarProjectSources.maximumFolderCount).map { "/Sources/Folder\($0)" }
        ]

        for folders in invalidSources {
            XCTAssertThrowsError(
                try organization.updateProject(path: "/Projects/New", name: "New", sourceFolders: folders)
            ) {
                XCTAssertEqual($0 as? SidebarOrganizationError, .invalidSourceFolders)
            }
            XCTAssertEqual(organization, original)
        }
        XCTAssertThrowsError(
            try organization.updateProject(path: "/Projects/New", name: "", sourceFolders: ["/Sources/Valid"])
        )
        XCTAssertEqual(organization, original)
        XCTAssertThrowsError(
            try organization.updateProject(path: "relative", name: "New", sourceFolders: ["/Sources/Valid"])
        )
        XCTAssertEqual(organization, original)
    }

    func testMaximumSourceCountIsAcceptedAndOrderIsPreserved() throws {
        var organization = SidebarOrganization()
        let sources = (0..<VyronSidebarProjectSources.maximumFolderCount).reversed().map { "/Sources/Folder\($0)" }

        try organization.updateProject(path: "/Projects/Combined", name: "Combined", sourceFolders: sources)

        XCTAssertEqual(organization.projectSourceFolders(for: "/Projects/Combined"), sources)
        XCTAssertEqual(try decode(encodedObject(organization)), organization)
    }

    func testRemovingProjectClearsSourceMetadataWithoutRemovingChatsOrSharedReferences() throws {
        var organization = SidebarOrganization()
        let removed = "/Projects/Removed"
        let kept = "/Projects/Kept"
        let source = "/Sources/Shared"
        let chatID = UUID()
        try organization.updateProject(path: removed, name: "Removed", sourceFolders: [source])
        try organization.updateProject(path: kept, name: "Kept", sourceFolders: [source])
        let folderID = try organization.createFolder(name: "Chats")
        try organization.move(.conversation(chatID), to: folderID)
        try organization.togglePin(.conversation(chatID))
        try organization.archiveConversations(ids: [chatID])

        organization.removeItem(.project(removed))
        try organization.registerProject(path: removed)

        XCTAssertEqual(organization.projectSourceFolders(for: removed), [removed])
        XCTAssertEqual(organization.projectSourceFolders(for: kept), [source])
        XCTAssertTrue(organization.contains(.conversation(chatID)))
        XCTAssertEqual(organization.folderID(for: .conversation(chatID)), folderID)
        XCTAssertTrue(organization.isPinned(.conversation(chatID)))
        XCTAssertTrue(organization.isConversationArchived(chatID))
        XCTAssertEqual(try decode(encodedObject(organization)), organization)
    }

    func testDecodingRejectsCorruptSourceRecords() throws {
        var organization = SidebarOrganization()
        let project = "/Projects/Kept"
        try organization.updateProject(path: project, name: "Kept", sourceFolders: ["/Sources/Kept"])
        let original = try encodedObject(organization)
        let invalidFolders = [
            [],
            ["relative"],
            ["/Sources/Old/../Kept"],
            ["/Sources/Kept", "/Sources/Kept"],
            (0...VyronSidebarProjectSources.maximumFolderCount).map { "/Sources/Folder\($0)" }
        ]
        for folders in invalidFolders {
            var stored = original
            stored["projectSources"] = [["path": project, "folders": folders]]
            XCTAssertThrowsError(try decode(stored))
        }
        var stored = original
        stored["projectSources"] = [["path": "/Projects/Missing", "folders": ["/Sources/Kept"]]]
        XCTAssertThrowsError(try decode(stored))
        stored = original
        stored["projectSources"] = [
            ["path": project, "folders": ["/Sources/First"]],
            ["path": project, "folders": ["/Sources/Second"]]
        ]
        XCTAssertThrowsError(try decode(stored))
    }

    private func encodedObject(_ organization: SidebarOrganization) throws -> [String: Any] {
        let data = try JSONEncoder().encode(organization)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> SidebarOrganization {
        try JSONDecoder().decode(SidebarOrganization.self, from: JSONSerialization.data(withJSONObject: object))
    }
}
