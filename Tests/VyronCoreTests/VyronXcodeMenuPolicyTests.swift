import Foundation
import XCTest
@testable import VyronAutomation

final class VyronXcodeMenuPolicyTests: XCTestCase {
    func testExactXcodeNavigationMenuLabelsAreRoutine() {
        for title in ["Product", "Window"] {
            XCTAssertTrue(isAutomatic(element(title), goal: "Check Finator"))
        }
    }

    func testBuildRunTestAndStopRequireExplicitUserOperations() {
        for (title, goal) in [
            ("Run", "Run Finator in the simulator"),
            ("Build", "Please build Finator"),
            ("Test", "Open Xcode and test Finator"),
            ("Stop", "Can you stop the app?"),
            ("Run", "Build and run the app")
        ] {
            XCTAssertTrue(isAutomatic(element(title, role: "AXMenuItem"), goal: goal), goal)
        }
    }

    func testWrongAppRoleAndUnrequestedOrQuotedOperationsStillNeedReview() {
        XCTAssertFalse(isAutomatic(element("Run", app: "com.example.Other", role: "AXMenuItem"), goal: "Run Finator"))
        XCTAssertFalse(isAutomatic(element("Run", role: "AXButton"), goal: "Run Finator"))
        for goal in ["Inspect runtime logs", "Explain how to run Finator", "Open Finator test results",
                     "Check the running app", "\"Run Finator\"", "> Run Finator", "Show me how to run Finator"] {
            XCTAssertFalse(isAutomatic(element("Run", role: "AXMenuItem"), goal: goal), goal)
        }
        for title in ["Archive", "Export", "Publish", "Download", "Install", "Run Script", "Product Settings"] {
            XCTAssertFalse(isAutomatic(element(title, role: "AXMenuItem"), goal: "Run Finator"), title)
        }
    }

    func testSensitiveNativeDescriptionsOverrideAnOtherwiseRoutineMenuLabel() {
        let target = NativeElementInfo(
            elementID: 1, applicationID: "com.apple.dt.Xcode", role: "AXMenuItem",
            title: "Run", description: "Publish and upload", value: "", actions: ["click"]
        )
        XCTAssertFalse(isAutomatic(target, goal: "Run Finator"))
    }

    private func element(
        _ title: String, app: String = "com.apple.dt.Xcode", role: String = "AXMenuBarItem"
    ) -> NativeElementInfo {
        NativeElementInfo(
            elementID: 1, applicationID: app, role: role, title: title,
            description: "", value: "", actions: ["click"]
        )
    }

    private func isAutomatic(_ element: NativeElementInfo, goal: String) -> Bool {
        if case .automatic = AutomationPolicy.evaluate(
            kind: "click", applicationID: element.applicationID, element: element, goal: goal
        ) { return true }
        return false
    }
}
