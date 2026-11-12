import Foundation
import XCTest
@testable import VyronCore

final class SidebarOrganizationMetadataTests: XCTestCase {
    func testLegacyVersionOneDecodesWithDefaultLabelsAndNoArchivedChats() throws {
        var original = SidebarOrganization()
        let chatID = UUID()
        try original.registerProject(path: "/Projects/Original")
        original.registerConversation(id: chatID)
        let folderID = try original.createFolder(name: "Work")
        try original.move(.project("/Projects/Original"), to: folderID)
        try original.togglePin(.conversation(chatID))
        var stored = try encodedObject(original)
        stored.removeValue(forKey: "projectNames")
        stored.removeValue(forKey: "archivedConversationIDs")

        let restored = try decode(stored)

        XCTAssertEqual(restored, original)
        XCTAssertEqual(restored.projectDisplayName(for: "/Projects/Original"), "Original")
        XCTAssertTrue(restored.archivedConversationIDs.isEmpty)
        XCTAssertEqual(restored.folderID(for: .project("/Projects/Original")), folderID)
        XCTAssertTrue(restored.isPinned(.conversation(chatID)))
    }

    func testProjectLabelsNormalizeAndRoundTripWithoutChangingProjectIdentity() throws {
        var organization = SidebarOrganization()
        let canonicalPath = "/Projects/ActualProject"
        try organization.renameProject(path: "/Projects/Old/../ActualProject", name: "  Cafe\u{301} App  ")

        let restored = try JSONDecoder().decode(
            SidebarOrganization.self,
            from: JSONEncoder().encode(organization)
        )

        XCTAssertEqual(restored, organization)
        XCTAssertEqual(restored.allProjects, [canonicalPath])
        XCTAssertEqual(restored.projectDisplayName(for: canonicalPath), "Café App")
        XCTAssertEqual(restored.projectDisplayName(for: "/Projects/Old/../ActualProject"), "Café App")
        XCTAssertEqual(restored.projectDisplayName(for: "/Projects/Unregistered"), "Unregistered")
        XCTAssertTrue(restored.contains(.project(canonicalPath)))
        XCTAssertFalse(restored.contains(.project("/Projects/Café App")))
    }

    func testInvalidProjectLabelsFailWithoutRegisteringOrChangingProjects() throws {
        var organization = SidebarOrganization()
        try organization.renameProject(path: "/Projects/Kept", name: "Kept Label")
        let original = organization

        for name in ["", " \n", "Bad\nName", "Bad\u{0}Name", String(repeating: "x", count: 81)] {
            XCTAssertThrowsError(try organization.renameProject(path: "/Projects/New", name: name)) { error in
                XCTAssertEqual(error as? SidebarOrganizationError, .invalidProjectName)
            }
            XCTAssertEqual(organization, original)
        }
        XCTAssertThrowsError(try organization.renameProject(path: "relative/path", name: "Valid Name"))
        XCTAssertEqual(organization, original)
    }

    func testArchiveAndRestorePreserveProjectFolderAndPinAssignments() throws {
        var organization = SidebarOrganization()
        let firstID = UUID()
        let secondID = UUID()
        let projectPath = "/Projects/Kept"
        try organization.registerProject(path: projectPath)
        let folderID = try organization.createFolder(name: "Work")
        try organization.move(.project(projectPath), to: folderID)
        try organization.move(.conversation(firstID), to: folderID)
        organization.registerConversation(id: secondID)
        try organization.togglePin(.conversation(firstID))
        let pinnedItems = organization.pinnedItems

        try organization.archiveConversations(ids: [firstID, secondID, firstID])
        var restored = try JSONDecoder().decode(
            SidebarOrganization.self,
            from: JSONEncoder().encode(organization)
        )

        XCTAssertEqual(restored, organization)
        XCTAssertEqual(restored.archivedConversationIDs, [firstID, secondID])
        XCTAssertTrue(restored.isConversationArchived(firstID))
        XCTAssertTrue(restored.contains(.conversation(firstID)))
        XCTAssertEqual(restored.folderID(for: .conversation(firstID)), folderID)
        XCTAssertEqual(restored.pinnedItems, pinnedItems)

        restored.restoreConversation(id: firstID)
        restored.restoreConversation(id: UUID())
        XCTAssertFalse(restored.isConversationArchived(firstID))
        XCTAssertTrue(restored.isConversationArchived(secondID))
        XCTAssertTrue(restored.isPinned(.conversation(firstID)))
        XCTAssertEqual(restored.folderID(for: .conversation(firstID)), folderID)
        XCTAssertEqual(restored.folderID(for: .project(projectPath)), folderID)
        XCTAssertEqual(restored.allProjects, [projectPath])
    }

    func testArchiveUnknownConversationIsAtomicAndRemovalClearsOnlyOwnedMetadata() throws {
        var organization = SidebarOrganization()
        let firstID = UUID()
        let secondID = UUID()
        try organization.renameProject(path: "/Projects/Removed", name: "Friendly Label")
        organization.registerConversation(id: firstID)
        organization.registerConversation(id: secondID)
        let original = organization

        XCTAssertThrowsError(try organization.archiveConversations(ids: [firstID, UUID()]))
        XCTAssertEqual(organization, original)
        try organization.archiveConversations(ids: [firstID, secondID])
        organization.removeItem(.conversation(firstID))
        organization.removeItem(.project("/Projects/Removed"))

        XCTAssertFalse(organization.contains(.conversation(firstID)))
        XCTAssertFalse(organization.isConversationArchived(firstID))
        XCTAssertTrue(organization.isConversationArchived(secondID))
        XCTAssertTrue(organization.contains(.conversation(secondID)))
        XCTAssertTrue(organization.allProjects.isEmpty)
        try organization.registerProject(path: "/Projects/Removed")
        XCTAssertEqual(organization.projectDisplayName(for: "/Projects/Removed"), "Removed")
        _ = try decode(encodedObject(organization))
    }

    func testDecodingRejectsOrphanedDuplicatedAndInvalidProjectLabelsAndArchives() throws {
        var organization = SidebarOrganization()
        let path = "/Projects/Kept"
        try organization.renameProject(path: path, name: "Valid Label")
        let original = try encodedObject(organization)
        let invalidLabels: [[[String: String]]] = [
            [["path": "/Projects/Missing", "name": "Missing"]],
            [["path": "/Projects/Old/../Kept", "name": "Not canonical"]],
            [["path": path, "name": "  Untrimmed  "]],
            [["path": path, "name": ""]],
            [["path": path, "name": "Bad\nLabel"]],
            [["path": path, "name": "First"], ["path": path, "name": "Second"]]
        ]

        for labels in invalidLabels {
            var stored = original
            stored["projectNames"] = labels
            XCTAssertThrowsError(try decode(stored))
        }
        var stored = original
        stored["archivedConversationIDs"] = [UUID().uuidString]
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
