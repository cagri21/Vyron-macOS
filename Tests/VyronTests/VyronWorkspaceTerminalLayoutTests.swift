import SwiftUI
import XCTest
@testable import Vyron

final class VyronWorkspaceTerminalLayoutTests: XCTestCase {
    func testDraggingUpExpandsAndDraggingDownShrinksTheTerminal() {
        XCTAssertEqual(
            VyronWorkspaceTerminalLayout.resizedHeight(start: 195, translation: -80, available: 800),
            275
        )
        XCTAssertEqual(
            VyronWorkspaceTerminalLayout.resizedHeight(start: 195, translation: 50, available: 800),
            145
        )
    }

    func testDraggingBeyondLimitsPreservesUsableTerminalAndConversationSpace() {
        XCTAssertEqual(
            VyronWorkspaceTerminalLayout.resizedHeight(start: 195, translation: 1_000, available: 800),
            120
        )
        XCTAssertEqual(
            VyronWorkspaceTerminalLayout.resizedHeight(start: 195, translation: -1_000, available: 800),
            499
        )
        XCTAssertEqual(800 - 499 - VyronWorkspaceStyle.dividerWidth, 300)
    }

    func testTemporaryWindowConstraintDoesNotReplaceThePreferredHeight() {
        let preferredHeight: CGFloat = 450

        XCTAssertEqual(VyronWorkspaceTerminalLayout.height(preferred: preferredHeight, available: 600), 299)
        XCTAssertEqual(VyronWorkspaceTerminalLayout.height(preferred: preferredHeight, available: 900), 450)
    }

    func testShortContainersReduceTheMinimumWithoutProducingNegativeHeight() {
        XCTAssertEqual(VyronWorkspaceTerminalLayout.height(preferred: 195, available: 400), 99)
        XCTAssertEqual(VyronWorkspaceTerminalLayout.height(preferred: 195, available: 301), 0)
        XCTAssertEqual(VyronWorkspaceTerminalLayout.height(preferred: 195, available: 100), 0)
        XCTAssertEqual(VyronWorkspaceTerminalLayout.height(preferred: -50, available: 0), 0)
    }
}
