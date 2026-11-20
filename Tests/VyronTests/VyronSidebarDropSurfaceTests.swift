import Foundation
import XCTest
@testable import Vyron
import VyronCore

final class VyronSidebarDropSurfaceTests: XCTestCase {
    func testProjectEdgesSelectBeforeAndAfterWithoutNesting() {
        let source = VyronSidebarRow.item(.project("/Projects/Source"))
        let target = VyronSidebarRow.item(.project("/Projects/Target"))
        let surface = projectDropSurface(path: "/Projects/Target")

        XCTAssertEqual(
            surface.destination(for: source, verticalPosition: 0.1),
            VyronSidebarDestination(group: .rootProjects, position: .before(target))
        )
        XCTAssertEqual(
            surface.destination(for: source, verticalPosition: 0.9),
            VyronSidebarDestination(group: .rootProjects, position: .after(target))
        )
    }

    func testProjectCenterAcceptsChatsAndRejectsProjects() {
        let targetPath = "/Projects/Target"
        let surface = projectDropSurface(path: targetPath)
        let chat = VyronSidebarRow.item(.conversation(UUID()))
        let project = VyronSidebarRow.item(.project("/Projects/Source"))

        XCTAssertEqual(
            surface.destination(for: chat, verticalPosition: 0.5),
            VyronSidebarDestination(group: .project(.init(path: targetPath)), position: .end)
        )
        XCTAssertNil(surface.destination(for: project, verticalPosition: 0.5))
    }

    func testChatDropUsesTargetChatsProjectAndPosition() {
        let source = Conversation(title: "Source", workspacePath: "/Projects/Source")
        let targetPath = "/Projects/Target"
        let target = Conversation(title: "Target", workspacePath: targetPath)
        let targetGroup = VyronSidebarGroup.project(.init(path: targetPath))
        let surface = VyronSidebarDropSurface.entry(
            VyronSidebarEntry(
                id: target.id.uuidString,
                kind: .chat(VyronSidebarChat(conversation: target, isPinned: false, showsProject: false)),
                depth: 1,
                group: targetGroup
            )
        )
        let sourceRow = VyronSidebarRow.item(.conversation(source.id))
        let targetRow = VyronSidebarRow.item(.conversation(target.id))

        XCTAssertEqual(
            surface.destination(for: sourceRow, verticalPosition: 0.2),
            VyronSidebarDestination(group: targetGroup, position: .before(targetRow))
        )
        XCTAssertEqual(
            surface.destination(for: sourceRow, verticalPosition: 0.8),
            VyronSidebarDestination(group: targetGroup, position: .after(targetRow))
        )
    }

    private func projectDropSurface(path: String) -> VyronSidebarDropSurface {
        .entry(
            VyronSidebarEntry(
                id: path,
                kind: .project(VyronSidebarProject(path: path, isPinned: false)),
                depth: 0,
                group: .rootProjects
            )
        )
    }
}
