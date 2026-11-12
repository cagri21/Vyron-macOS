import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronWorkspaceTabsTests: XCTestCase {
    func testConversationTabRemainsWhenOtherTabsClose() throws {
        let model = VyronWorkspaceTabsModel()
        let conversationID = model.selectedID
        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertEqual(model.selectedTab.kind, .conversation)
        XCTAssertFalse(model.close(conversationID))
        let home = try XCTUnwrap(model.newTab())
        XCTAssertTrue(model.close(home))
        XCTAssertEqual(model.selectedID, conversationID)
        XCTAssertEqual(model.tabs.count, 1)
        XCTAssertFalse(model.close(UUID()))
    }

    func testSwitchingTabsPreservesTheirLocations() throws {
        let model = VyronWorkspaceTabsModel()
        let home = try XCTUnwrap(model.newTab())
        let url = try XCTUnwrap(URL(string: "https://example.com/docs"))
        let web = try XCTUnwrap(model.openWebsite(url))
        XCTAssertEqual(model.selectedID, web)
        XCTAssertTrue(model.select(home))
        XCTAssertEqual(model.selectedTab.kind, .home)
        XCTAssertTrue(model.select(web))
        XCTAssertEqual(model.selectedTab.location, .website(VyronWorkspaceWebsiteLocation(url: url)))
        XCTAssertFalse(model.select(UUID()))
        XCTAssertEqual(model.selectedID, web)
    }

    func testClosingActiveTabChoosesRightNeighborThenLeft() throws {
        let model = VyronWorkspaceTabsModel()
        let first = try XCTUnwrap(model.newTab())
        let middle = try XCTUnwrap(model.newTab())
        let last = try XCTUnwrap(model.newTab())
        XCTAssertTrue(model.select(middle))
        XCTAssertTrue(model.close(middle))
        XCTAssertEqual(model.selectedID, last)
        XCTAssertTrue(model.close(last))
        XCTAssertEqual(model.selectedID, first)
        XCTAssertTrue(model.close(first))
        XCTAssertEqual(model.selectedID, model.conversationTabID)
    }

    func testClosingBackgroundTabKeepsSelection() throws {
        let model = VyronWorkspaceTabsModel()
        let first = try XCTUnwrap(model.newTab())
        let second = try XCTUnwrap(model.newTab())
        XCTAssertTrue(model.close(first))
        XCTAssertEqual(model.selectedID, second)
    }

    func testNavigateReplacesHomeWithoutCreatingOrReplacingConversation() throws {
        let model = VyronWorkspaceTabsModel()
        let home = try XCTUnwrap(model.newTab())
        let first = try XCTUnwrap(URL(string: "https://example.com/first"))
        let second = try XCTUnwrap(URL(string: "https://example.com/second"))
        XCTAssertTrue(model.navigate(first, in: home))
        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.selectedTab.kind, .website)
        XCTAssertTrue(model.navigate(second, in: home))
        XCTAssertEqual(model.selectedTab.location, .website(VyronWorkspaceWebsiteLocation(url: second)))
        XCTAssertFalse(model.navigate(first, in: model.conversationTabID))
        XCTAssertFalse(model.navigate(first, in: UUID()))
        XCTAssertEqual(model.tabs.first?.kind, .conversation)
    }

    func testSavedPageReusesItsTabAndUpdatesTitle() throws {
        let model = VyronWorkspaceTabsModel()
        var page = VyronWorkspacePage(title: "Notes")
        let tabID = try XCTUnwrap(model.openPage(page))
        XCTAssertTrue(model.select(model.conversationTabID))
        page.title = "Revised notes"
        XCTAssertEqual(model.openPage(page), tabID)
        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.selectedID, tabID)
        XCTAssertEqual(model.selectedTab.title, page.title)
        page.title = "Final notes"
        model.updatePageTitle(page)
        XCTAssertEqual(model.selectedTab.title, page.title)
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        XCTAssertFalse(model.navigate(url, in: tabID))
    }

    func testWebsiteUpdateOnlyChangesItsExistingTab() throws {
        let model = VyronWorkspaceTabsModel()
        let first = try XCTUnwrap(URL(string: "https://example.com"))
        let redirected = try XCTUnwrap(URL(string: "https://example.org/docs"))
        let id = try XCTUnwrap(model.openWebsite(first))
        XCTAssertTrue(model.updateWebsiteLocation(
            VyronWorkspaceWebsiteUpdate(tabID: id, url: redirected, title: "Documentation")
        ))
        XCTAssertEqual(model.selectedTab.location, .website(VyronWorkspaceWebsiteLocation(url: redirected)))
        XCTAssertEqual(model.selectedTab.title, "Documentation")
        XCTAssertTrue(model.close(id))
        XCTAssertFalse(model.updateWebsiteLocation(VyronWorkspaceWebsiteUpdate(tabID: id, url: first)))
        XCTAssertEqual(model.tabs.count, 1)
    }

    func testUnsupportedURLsCannotOpenOrReplaceTabs() throws {
        let model = VyronWorkspaceTabsModel()
        let home = try XCTUnwrap(model.newTab())
        for address in ["file:///etc/passwd", "javascript:alert(1)", "https://user:password@example.com"] {
            let url = try XCTUnwrap(URL(string: address))
            XCTAssertNil(model.openWebsite(url))
            XCTAssertFalse(model.navigate(url, in: home))
        }
        XCTAssertEqual(model.tabs.count, 2)
        XCTAssertEqual(model.selectedTab.kind, .home)
    }

    func testTabLimitKeepsSelectionAndPageReuseWorking() throws {
        let model = VyronWorkspaceTabsModel()
        let page = VyronWorkspacePage(title: "Notes")
        let pageID = try XCTUnwrap(model.openPage(page))
        for _ in 0..<(VyronWorkspaceTabLimits.maximumTabs - 2) {
            XCTAssertNotNil(model.newTab())
        }
        let selected = model.selectedID
        XCTAssertNil(model.newTab())
        XCTAssertEqual(model.selectedID, selected)
        XCTAssertEqual(model.tabs.count, VyronWorkspaceTabLimits.maximumTabs)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.openPage(page), pageID)
        XCTAssertEqual(model.selectedID, pageID)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.close(selected))
        XCTAssertNotNil(model.newTab())
        XCTAssertNil(model.errorMessage)
    }

    func testConversationTitleUpdatePreservesTabIdentityAndSelection() throws {
        let model = VyronWorkspaceTabsModel()
        let selected = try XCTUnwrap(model.newTab())
        model.updateConversationTitle("Current task")
        XCTAssertEqual(model.tabs.first?.id, model.conversationTabID)
        XCTAssertEqual(model.tabs.first?.title, "Current task")
        XCTAssertEqual(model.selectedID, selected)
    }
}
