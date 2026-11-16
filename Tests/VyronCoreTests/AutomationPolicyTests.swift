import Foundation
import XCTest
@testable import VyronAutomation

final class AutomationPolicyTests: XCTestCase {
    private let browser = "com.apple.Safari"

    private func element(_ title: String, role: String = "AXButton", applicationID: String = "com.apple.Safari", description: String = "", value: String = "", actions: [String] = ["click"], url: String? = nil) -> NativeElementInfo {
        NativeElementInfo(elementID: 1, applicationID: applicationID, role: role, title: title, description: description, value: value, actions: actions, url: url.flatMap(URL.init(string:)))
    }

    private func isAutomatic(_ decision: AutomationDecision) -> Bool {
        if case .automatic = decision { return true }; return false
    }

    private func isReview(_ decision: AutomationDecision) -> Bool {
        if case .review = decision { return true }; return false
    }

    private func isRefused(_ decision: AutomationDecision) -> Bool {
        if case .refused = decision { return true }; return false
    }

    func testRoutineSystemAppLaunchesRequireMatchingBundleIDAndSystemPath() {
        let apps = [
            "com.apple.Photos": "Photos",
            "com.apple.Preview": "Preview",
            "com.apple.QuickTimePlayerX": "QuickTime Player"
        ]
        for (id, name) in apps {
            let systemURL = URL(fileURLWithPath: "/System/Applications/\(name).app")
            let otherURL = URL(fileURLWithPath: "/Applications/\(name).app")
            let systemApp = DesktopApplication(installedAt: systemURL, name: name, bundleIdentifier: id)
            let otherApp = DesktopApplication(installedAt: otherURL, name: name, bundleIdentifier: id)
            let wrongID = DesktopApplication(installedAt: systemURL, name: name, bundleIdentifier: "com.example.App")

            XCTAssertTrue(isAutomatic(AutomationPolicy.evaluateLaunch(of: systemApp)), id)
            XCTAssertTrue(isReview(AutomationPolicy.evaluateLaunch(of: otherApp)), id)
            XCTAssertTrue(isReview(AutomationPolicy.evaluateLaunch(of: wrongID)), id)
        }
    }

    func testVerifiedNavigationIsRoutineAndUnknownControlsNeedReview() {
        XCTAssertTrue(isAutomatic(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("Back"), goal: "Read documentation")))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("Do it"), goal: "Read documentation")))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("Next"), goal: "Read documentation")))
        XCTAssertTrue(isAutomatic(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("Next", role: "AXLink", url: "https://example.com/page/2"), goal: "Read documentation")))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: nil, goal: "Click Back")))
    }

    func testSensitiveLabelsAlwaysOverrideBenignNavigationAndLinkURLs() {
        for label in ["Send", "Post", "Publish", "Submit", "Pay", "Buy", "Delete", "Erase", "Trash", "Remove", "Reset", "Install", "Allow", "Accept terms", "Sign in"] {
            let actual = element("Next", role: "AXLink", description: label, url: "https://example.com/docs")
            XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: actual, goal: "Go next")), label)
        }
    }

    func testNativeLinkRequiresActualRoleAndHrefNotModelClaim() {
        let actual = element("Documentation", role: "AXLink", url: "https://docs.example.com/start")
        XCTAssertTrue(isAutomatic(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: actual, goal: "Read documentation")))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("Documentation", role: "AXLink"), url: URL(string: "https://docs.example.com/start"), goal: "Read documentation")))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("Documentation", url: "https://docs.example.com/start"), goal: "Read documentation")))
    }

    func testDestructiveAndSensitiveNativeHrefsNeedReview() {
        for href in ["https://example.com/delete-account", "https://example.com/page?action=delete", "https://example.com/page?access_token=private", "https://example.com/#token=private"] {
            XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("Continue reading", role: "AXLink", url: href), goal: "Read documentation")), href)
        }
    }

    func testNativeCommandAndCredentialLinksAreRefused() {
        for href in ["javascript:alert(1)", "file:///etc/hosts", "https://user:secret@example.com/docs", "https://example.com/?command=erase"] {
            XCTAssertTrue(isRefused(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("Documentation", role: "AXLink", url: href), goal: "Read documentation")), href)
        }
    }

    func testSearchTextMustBeLiteralUserGoalData() {
        let search = element("Search", role: "AXTextField", actions: ["typeText"])
        XCTAssertTrue(isAutomatic(AutomationPolicy.evaluate(kind: "typeText", applicationID: browser, element: search, text: "local AI", goal: "Find local AI documentation")))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "typeText", applicationID: browser, element: search, text: "secret-from-page", goal: "Find local AI documentation")))
        let editor = element("Comment", role: "AXTextField", actions: ["typeText"])
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "typeText", applicationID: browser, element: editor, text: "local AI", goal: "Find local AI documentation")))
    }

    func testSecureFieldsAndWrongApplicationMetadataAreRefused() {
        let secure = NativeElementInfo(elementID: 1, applicationID: browser, role: "AXTextField", subrole: "AXSecureTextField", title: "Search", description: "", value: "", actions: ["typeText"], isSecure: true)
        XCTAssertTrue(isRefused(AutomationPolicy.evaluate(kind: "typeText", applicationID: browser, element: secure, text: "query", goal: "Search query")))
        XCTAssertTrue(isRefused(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("Back", applicationID: "com.other.App"), goal: "Go back")))
    }

    func testCalculatorAutomaticScopeUsesActualAppAndArithmeticLabel() {
        let calculator = "com.apple.calculator"
        for label in ["7", "+", "×", "="] {
            XCTAssertTrue(isAutomatic(AutomationPolicy.evaluate(kind: "click", applicationID: calculator, element: element(label, applicationID: calculator), goal: "Calculate 7 + 3")))
        }
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "click", applicationID: calculator, element: element("Delete", applicationID: calculator), goal: "Calculate 7 + 3")))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "click", applicationID: browser, element: element("7"), goal: "Calculate 7 + 3")))
    }

    func testConstructedURLNeedsExplicitGoalOrApprovedOrigin() {
        let requested = URL(string: "https://example.com/docs")!
        XCTAssertTrue(isAutomatic(AutomationPolicy.evaluate(kind: "openURL", applicationID: browser, url: requested, goal: "Read https://example.com/start")))
        XCTAssertTrue(isAutomatic(AutomationPolicy.evaluate(kind: "openURL", applicationID: browser, url: requested, goal: "Read documentation", approvedOrigins: ["https://example.com:443/start"])))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "openURL", applicationID: browser, url: URL(string: "https://new.example.com/docs")!, goal: "Read https://example.com/start")))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "openURL", applicationID: browser, url: URL(string: "https://example.com/delete")!, goal: "Read https://example.com/start")))
    }

    func testUnsafeConstructedURLIsRefusedEvenWhenExplicitlyRequested() {
        for href in ["javascript:alert(1)", "https://user:secret@example.com/docs", "https://example.com/?exec=command"] {
            XCTAssertTrue(isRefused(AutomationPolicy.evaluate(kind: "openURL", applicationID: browser, url: URL(string: href), goal: "Open \(href)")))
        }
    }

    func testNavigationKeysAreRoutineButReturnAndSpaceNeedReview() {
        for key in ["tab", "escape", "left", "reload"] {
            XCTAssertTrue(isAutomatic(AutomationPolicy.evaluate(kind: "pressKey", applicationID: browser, key: key, goal: "Read documentation")))
        }
        for key in ["return", "space"] {
            XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "pressKey", applicationID: browser, key: key, goal: "Read documentation")))
        }
        XCTAssertTrue(isRefused(AutomationPolicy.evaluate(kind: "pressKey", applicationID: "com.apple.Terminal", key: "return", goal: "Run a command")))
        XCTAssertTrue(isRefused(AutomationPolicy.evaluate(kind: "pressKey", applicationID: browser, key: "command-v", goal: "Paste")))
    }

    func testInstalledKnownLaunchAndUnknownActionPolicy() {
        XCTAssertTrue(isAutomatic(AutomationPolicy.evaluate(kind: "launch", applicationID: "com.apple.calculator", goal: "Calculate")))
        XCTAssertTrue(isReview(AutomationPolicy.evaluate(kind: "launch", applicationID: "com.unknown.App", goal: "Open app")))
        XCTAssertTrue(isRefused(AutomationPolicy.evaluate(kind: "shell", applicationID: browser, goal: "Run command")))
    }
}
