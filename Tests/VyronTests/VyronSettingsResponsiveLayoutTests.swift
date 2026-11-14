import XCTest
@testable import Vyron

final class VyronSettingsResponsiveLayoutTests: XCTestCase {
    func testSettingsSidebarCollapsesBelowItsFullLayoutWidth() {
        XCTAssertFalse(VyronSettingsStyle.shouldCollapseSidebar(availableWidth: 901))
        XCTAssertTrue(VyronSettingsStyle.shouldCollapseSidebar(availableWidth: 900))
    }

    func testCollapsedSettingsLayoutKeepsTheContentAtItsMinimumWidth() {
        XCTAssertEqual(
            VyronSettingsStyle.collapsedMinimumWidth,
            VyronSettingsStyle.collapsedSidebarWidth
                + VyronSettingsStyle.dividerWidth
                + VyronSettingsStyle.minimumContentWidth
        )
    }
}
