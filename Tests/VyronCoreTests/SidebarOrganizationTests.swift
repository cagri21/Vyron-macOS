import Foundation
import XCTest
@testable import VyronCore

final class SidebarOrganizationTests: XCTestCase {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("vyron-sidebar-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testNestedMovesRejectCyclesWithoutChangingTheOrganization() throws {
        var organization = SidebarOrganization()
        let parent = try organization.createFolder(name: "Work")
        let child = try organization.createFolder(name: "Apps", parentID: parent)
        let leaf = try organization.createFolder(name: "Native", parentID: child)
        XCTAssertEqual(organization.breadcrumb(for: leaf).map(\.name), ["Work", "Apps", "Native"])
        let before = organization
        for target in [parent, child, leaf] {
            XCTAssertThrowsError(try organization.moveFolder(id: parent, toParent: target)) { error in
                XCTAssertEqual(error as? SidebarOrganizationError, .folderCycle)
            }
            XCTAssertEqual(organization, before)
        }
        XCTAssertThrowsError(try organization.moveFolder(id: leaf, toParent: UUID()))
        XCTAssertEqual(organization, before)
        try organization.moveFolder(id: leaf, toParent: nil)
        XCTAssertEqual(organization.breadcrumb(for: leaf).map(\.name), ["Native"])
    }

    func testSiblingNamesAreUniqueAcrossCreationRenameAndMove() throws {
        var organization = SidebarOrganization()
        let work = try organization.createFolder(name: " Work ")
        let personal = try organization.createFolder(name: "Personal")
        let apps = try organization.createFolder(name: "Apps", parentID: work)
        let otherApps = try organization.createFolder(name: "Apps", parentID: personal)
        XCTAssertThrowsError(try organization.createFolder(name: "work"))
        XCTAssertThrowsError(try organization.renameFolder(id: personal, name: "WORK"))
        XCTAssertThrowsError(try organization.moveFolder(id: otherApps, toParent: work))
        XCTAssertEqual(organization.folderChildren(of: work).map(\.id), [apps])
        XCTAssertEqual(organization.folderChildren(of: personal).map(\.id), [otherApps])
        for name in ["", " \n", "Bad\nName", String(repeating: "x", count: 81)] {
            XCTAssertThrowsError(try organization.createFolder(name: name))
        }
    }

    func testRemovingFolderReparentsContentsAndChildrenAndPreservesPinsAndIDs() throws {
        var organization = SidebarOrganization()
        let parent = try organization.createFolder(name: "Work")
        let removed = try organization.createFolder(name: "Archive", parentID: parent)
        _ = try organization.createFolder(name: "Apps", parentID: parent)
        let child = try organization.createFolder(name: "Apps", parentID: removed)
        let descendant = try organization.createFolder(name: "Swift", parentID: child)
        let project = SidebarItem.project("/Projects/OfflineApp")
        let conversation = SidebarItem.conversation(UUID())
        try organization.move(project, to: removed)
        try organization.move(conversation, to: removed)
        try organization.togglePin(project)
        try organization.togglePin(conversation)
        try organization.removeFolder(id: removed)
        XCTAssertEqual(organization.folderID(for: project), parent)
        XCTAssertEqual(organization.folderID(for: conversation), parent)
        XCTAssertEqual(organization.breadcrumb(for: descendant).map(\.name), ["Work", "Apps (2)", "Swift"])
        XCTAssertEqual(organization.breadcrumb(for: descendant).last?.id, descendant)
        XCTAssertEqual(organization.pinnedItems, [project, conversation])
        XCTAssertTrue(organization.contains(project))
        XCTAssertTrue(organization.contains(conversation))
        try organization.removeFolder(id: parent)
        XCTAssertNil(organization.folderID(for: project))
        XCTAssertNil(organization.folderID(for: conversation))
        XCTAssertTrue(organization.items(in: nil).contains(project))
        XCTAssertEqual(organization.breadcrumb(for: child).map(\.id), [child])
    }

    func testRegistryHasNoRecentLimitAndPinOrderAndCollapsedStateSurviveEncoding() throws {
        var organization = SidebarOrganization()
        for index in 0..<24 { try organization.registerProject(path: "/Projects/App\(index)") }
        let folder = try organization.createFolder(name: "Projects")
        let project = SidebarItem.project("/Projects/App0")
        let chat = SidebarItem.conversation(UUID())
        try organization.move(project, to: folder)
        try organization.move(chat, to: folder)
        try organization.togglePin(chat)
        try organization.togglePin(project)
        try organization.setFolderExpanded(folder, expanded: false)
        try organization.setProjectExpanded("/Projects/App0", expanded: false)
        let decoded = try JSONDecoder().decode(SidebarOrganization.self, from: JSONEncoder().encode(organization))
        XCTAssertEqual(decoded, organization)
        XCTAssertEqual(decoded.allProjects.count, 24)
        XCTAssertEqual(decoded.pinnedItems, [chat, project])
        XCTAssertFalse(decoded.isFolderExpanded(folder))
        XCTAssertFalse(decoded.isProjectExpanded("/Projects/App0"))
        XCTAssertTrue(decoded.isProjectExpanded("/Projects/App23"))
        XCTAssertEqual(decoded.items(in: folder), [project, chat], "Placement queries include pinned items")
    }

    func testItemRemovalAndRootMovesDoNotRemoveOtherRegistrations() throws {
        var organization = SidebarOrganization()
        let folder = try organization.createFolder(name: "Work")
        let project = SidebarItem.project("/Projects/App/../Kept")
        let chat = SidebarItem.conversation(UUID())
        try organization.move(project, to: folder)
        try organization.move(chat, to: folder)
        try organization.togglePin(project)
        try organization.togglePin(chat)
        XCTAssertEqual(organization.allProjects, ["/Projects/Kept"])
        try organization.move(chat, to: nil)
        XCTAssertNil(organization.folderID(for: chat))
        XCTAssertTrue(organization.isPinned(chat))
        organization.removeItem(chat)
        XCTAssertTrue(organization.conversationIDs.isEmpty)
        XCTAssertFalse(organization.isPinned(chat))
        XCTAssertTrue(organization.contains(project))
        organization.removeItem(project)
        XCTAssertTrue(organization.allProjects.isEmpty)
        XCTAssertTrue(organization.pinnedItems.isEmpty)
        XCTAssertEqual(organization.folderChildren(of: nil).map(\.id), [folder])
        XCTAssertThrowsError(try organization.registerProject(path: "relative/path"))
    }

    func testDecodingRejectsCyclesUnknownPlacementsAndFutureVersions() throws {
        var organization = SidebarOrganization()
        let parent = try organization.createFolder(name: "Work")
        let child = try organization.createFolder(name: "Apps", parentID: parent)
        try organization.move(.project("/Projects/App"), to: child)
        let encoded = try JSONEncoder().encode(organization)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["version"] = 2
        XCTAssertThrowsError(try JSONDecoder().decode(SidebarOrganization.self, from: JSONSerialization.data(withJSONObject: object)))
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var folders = try XCTUnwrap(object["folders"] as? [[String: Any]])
        folders[0]["parentID"] = child.uuidString
        object["folders"] = folders
        XCTAssertThrowsError(try JSONDecoder().decode(SidebarOrganization.self, from: JSONSerialization.data(withJSONObject: object)))
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["allProjects"] = []
        XCTAssertThrowsError(try JSONDecoder().decode(SidebarOrganization.self, from: JSONSerialization.data(withJSONObject: object)))
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["pinnedItems"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([SidebarItem.project("/Projects/Other/../App")]))
        XCTAssertThrowsError(try JSONDecoder().decode(SidebarOrganization.self, from: JSONSerialization.data(withJSONObject: object)), "Stored item identities must use the same canonical project path as placement queries")
    }

    func testPrivateAtomicStoreDistinguishesMissingAndValidEmptyAndPersistsUpdates() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SidebarOrganizationStore(fileURL: root.appendingPathComponent("Private/sidebar.json"))
        XCTAssertNil(try store.load())
        try store.save(SidebarOrganization())
        XCTAssertEqual(try store.load(), SidebarOrganization(), "Valid empty organization must not trigger migration")
        var organization = SidebarOrganization()
        let folder = try organization.createFolder(name: "Work")
        try organization.move(.project("/Missing/OfflineProject"), to: folder)
        try organization.togglePin(.project("/Missing/OfflineProject"))
        try store.save(organization)
        XCTAssertEqual(try SidebarOrganizationStore(fileURL: store.fileURL).load(), organization)
        let directoryAttributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.deletingLastPathComponent().path)
        let fileAttributes = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
        XCTAssertEqual((directoryAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((fileAttributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.fileURL.deletingLastPathComponent().path), ["sidebar.json"])
    }

    func testCorruptOriginalCannotBeOverwrittenEvenWhenCallerIgnoresLoadFailure() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sidebar.json")
        let original = Data("{ truncated original sidebar".utf8)
        try original.write(to: file)
        let store = SidebarOrganizationStore(fileURL: file)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(SidebarOrganization())) { error in
            guard case .unreadableStore = error as? SidebarOrganizationError else { return XCTFail("Expected a preserved unreadable-store error") }
        }
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["sidebar.json"])
    }

    func testVirtualOrganizationNeverRenamesOrRemovesReferencedProjectFiles() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let project = root.appendingPathComponent("ActualProject")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let source = project.appendingPathComponent("Keep.swift")
        let contents = Data("let keep = true\n".utf8)
        try contents.write(to: source)
        var organization = SidebarOrganization()
        let folder = try organization.createFolder(name: "Organized")
        try organization.move(.project(project.path), to: folder)
        try organization.togglePin(.project(project.path))
        try organization.renameFolder(id: folder, name: "Renamed")
        try organization.removeFolder(id: folder)
        organization.removeItem(.project(project.path))
        XCTAssertEqual(try Data(contentsOf: source), contents)
        XCTAssertTrue(FileManager.default.fileExists(atPath: project.path))
    }

    func testSymlinkStoreIsRejectedWithoutTouchingItsTarget() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("original.json")
        let contents = try JSONEncoder().encode(SidebarOrganization())
        try contents.write(to: target)
        let link = root.appendingPathComponent("sidebar.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = SidebarOrganizationStore(fileURL: link)
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.save(SidebarOrganization()))
        XCTAssertEqual(try Data(contentsOf: target), contents)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: link.path), target.path)
    }
}
