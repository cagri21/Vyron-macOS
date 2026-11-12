import SwiftUI
import XCTest
@testable import Vyron

final class VyronWorkspaceSplitConfigurationTests: XCTestCase {
    func testResizingUsesOppositeDirectionsAtTheTwoEdges() {
        let sidebar = VyronWorkspaceSplitConfiguration.sidebar(minimumContentWidth: 560)
        let inspector = VyronWorkspaceSplitConfiguration.inspector

        XCTAssertEqual(sidebar.resizedPanelWidth(start: 350, translation: 50, available: 1_400), 400)
        XCTAssertEqual(sidebar.resizedPanelWidth(start: 350, translation: -50, available: 1_400), 300)
        XCTAssertEqual(inspector.resizedPanelWidth(start: 350, translation: 50, available: 1_400), 300)
        XCTAssertEqual(inspector.resizedPanelWidth(start: 350, translation: -50, available: 1_400), 400)
    }

    func testDraggingBeyondEitherSidebarLimitKeepsItsSupportedSize() {
        let sidebar = VyronWorkspaceSplitConfiguration.sidebar(minimumContentWidth: 560)

        XCTAssertEqual(sidebar.resizedPanelWidth(start: 300, translation: -1_000, available: 1_400), 220)
        XCTAssertEqual(sidebar.resizedPanelWidth(start: 300, translation: 1_000, available: 1_400), 480)
    }

    func testDraggingBeyondEitherInspectorLimitKeepsItsSupportedSize() {
        let inspector = VyronWorkspaceSplitConfiguration.inspector

        XCTAssertEqual(inspector.resizedPanelWidth(start: 330, translation: 1_000, available: 1_400), 260)
        XCTAssertEqual(inspector.resizedPanelWidth(start: 330, translation: -1_000, available: 1_400), 640)
    }

    func testWindowConstraintReservesTheConversationAndDivider() {
        let sidebar = VyronWorkspaceSplitConfiguration.sidebar(minimumContentWidth: 560)
        let inspector = VyronWorkspaceSplitConfiguration.inspector
        let availableWidth: CGFloat = 900

        XCTAssertEqual(sidebar.panelWidth(preferred: 480, available: availableWidth), 339)
        XCTAssertEqual(inspector.panelWidth(preferred: 640, available: availableWidth), 339)
        XCTAssertEqual(availableWidth - 339 - VyronWorkspaceStyle.dividerWidth, 560)
    }

    func testNestedPanelsReserveBothDividersAndTheConversationMinimum() {
        let inspector = VyronWorkspaceSplitConfiguration.inspector
        let inspectorMinimum = inspector.panelWidths.lowerBound
        let sidebar = VyronWorkspaceSplitConfiguration.sidebar(
            minimumContentWidth: inspectorMinimum + 560 + VyronWorkspaceStyle.dividerWidth
        )
        let availableWidth: CGFloat = 1_200

        let sidebarWidth = sidebar.panelWidth(preferred: 480, available: availableWidth)
        let workspaceWidth = availableWidth - sidebarWidth - VyronWorkspaceStyle.dividerWidth
        let inspectorWidth = inspector.panelWidth(preferred: 640, available: workspaceWidth)
        let conversationWidth = workspaceWidth - inspectorWidth - VyronWorkspaceStyle.dividerWidth

        XCTAssertEqual(sidebarWidth, 378)
        XCTAssertEqual(inspectorWidth, 260)
        XCTAssertEqual(conversationWidth, 560)
    }

    func testTemporaryWindowConstraintDoesNotReplaceThePreferredWidth() {
        let inspector = VyronWorkspaceSplitConfiguration.inspector
        let preferredWidth: CGFloat = 500

        XCTAssertEqual(inspector.panelWidth(preferred: preferredWidth, available: 900), 339)
        XCTAssertEqual(inspector.panelWidth(preferred: preferredWidth, available: 1_400), 500)
    }
}
