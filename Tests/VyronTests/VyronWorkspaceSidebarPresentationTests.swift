import XCTest
@testable import Vyron

final class VyronWorkspaceSidebarPresentationTests: XCTestCase {
    func testNarrowingHidesTheDockedSidebarAndWideningRestoresIt() {
        let sidebar = VyronWorkspaceSidebarPresentation()

        XCTAssertEqual(sidebar.panelPresentation(isCompact: false), .docked)
        XCTAssertEqual(sidebar.panelPresentation(isCompact: true), .hidden)
        XCTAssertEqual(sidebar.panelPresentation(isCompact: false), .docked)
    }

    func testManuallyHiddenSidebarStaysHiddenAfterResizing() {
        var sidebar = VyronWorkspaceSidebarPresentation()
        sidebar.toggle(isCompact: false)

        XCTAssertEqual(sidebar.panelPresentation(isCompact: false), .hidden)
        XCTAssertEqual(sidebar.panelPresentation(isCompact: true), .hidden)
        XCTAssertEqual(sidebar.panelPresentation(isCompact: false), .hidden)

        sidebar.toggle(isCompact: false)
        XCTAssertEqual(sidebar.panelPresentation(isCompact: false), .docked)
    }

    func testCompactOverlayDoesNotChangeTheDockedPreference() {
        let preferredPresentations: [VyronWorkspacePanelPresentation] = [.docked, .hidden]
        for preferredPresentation in preferredPresentations {
            var sidebar = VyronWorkspaceSidebarPresentation()
            if preferredPresentation == .hidden {
                sidebar.toggle(isCompact: false)
            }

            sidebar.toggle(isCompact: true)
            XCTAssertEqual(sidebar.panelPresentation(isCompact: true), .overlay)
            XCTAssertEqual(sidebar.panelPresentation(isCompact: false), preferredPresentation)

            sidebar.dismissOverlay()
            XCTAssertEqual(sidebar.panelPresentation(isCompact: true), .hidden)
            XCTAssertEqual(sidebar.panelPresentation(isCompact: false), preferredPresentation)
        }
    }

    func testTogglingTheCompactOverlayTwiceClosesIt() {
        var sidebar = VyronWorkspaceSidebarPresentation()
        sidebar.toggle(isCompact: true)
        sidebar.toggle(isCompact: true)

        XCTAssertEqual(sidebar.panelPresentation(isCompact: true), .hidden)
        XCTAssertEqual(sidebar.panelPresentation(isCompact: false), .docked)
    }

    func testDockingRequiresEnoughRoomForTheSidebarAndVisibleInspector() {
        let conversationMinimumWidth = VyronWorkspaceStyle.minimumConversationWidth
        let inspectorMinimumWidth = VyronWorkspaceSplitConfiguration.inspector.panelWidths.lowerBound
        let sidebar = VyronWorkspaceSplitConfiguration.sidebar(minimumContentWidth: conversationMinimumWidth)
        let sidebarWithInspector = VyronWorkspaceSplitConfiguration.sidebar(
            minimumContentWidth: conversationMinimumWidth + inspectorMinimumWidth + VyronWorkspaceStyle.dividerWidth
        )

        // Split widths start after the icon rail.
        XCTAssertFalse(sidebar.canDockPanel(available: 780))
        XCTAssertTrue(sidebar.canDockPanel(available: 781))
        XCTAssertFalse(sidebarWithInspector.canDockPanel(available: 1_041))
        XCTAssertTrue(sidebarWithInspector.canDockPanel(available: 1_042))
    }
}
