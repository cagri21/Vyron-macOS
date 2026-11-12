import XCTest
import VyronCore

final class VyronAssistantRequestPolicyTests: XCTestCase {
    func testExplicitWebsiteScopeRoutesToSiteAnalysisWithOrWithoutAnOpenProject() {
        for projectIsOpen in [false, true] {
            for request in [
                "Analyze the entire website https://example.com",
                "Analyze https://example.com and all its subpages",
                "Analyze all subpages of https://example.com",
                "Analyze every page of https://example.com/readme",
                "Site-wide analysis of https://example.com"
            ] {
                XCTAssertEqual(
                    VyronAssistantRequestPolicy.classify(request, projectIsOpen: projectIsOpen),
                    .websiteAnalysis,
                    request
                )
            }
        }
    }

    func testSiteAnalysisRequiresAnExplicitRequestOutsideQuotedOrCodingInstructions() {
        for request in ["Analyze https://example.com/one", "Analyze https://example.com/sitewide"] {
            XCTAssertEqual(VyronAssistantRequestPolicy.classify(request), .webSearch)
        }
        XCTAssertEqual(VyronAssistantRequestPolicy.classify("Review all pages in the attached document"), .standard)
        for request in [
            "\"Analyze the entire website https://example.com\"",
            "Implement a feature to analyze all subpages of https://example.com"
        ] {
            XCTAssertEqual(VyronAssistantRequestPolicy.classify(request, projectIsOpen: true), .standard)
        }
    }

    func testEverydayWebResearchRemainsAvailableWithAProjectOpen() {
        for projectIsOpen in [false, true] {
            for request in [
                "list me pharmacies in istanbul. 10 only",
                "Find restaurants near me",
                "Search the web for current information about Istanbul",
                "Check online whether this museum is open",
                "İstanbul'da nöbetçi eczane bul"
            ] {
                XCTAssertEqual(
                    VyronAssistantRequestPolicy.classify(request, projectIsOpen: projectIsOpen),
                    .webSearch,
                    request
                )
            }
        }
    }

    func testExplicitMacRequestsUseNativeControllerWithOrWithoutAProject() {
        for projectIsOpen in [false, true] {
            for request in [
                "Open Safari",
                "Can you open Calculator?",
                "Please click the Safari search button",
                "Delete the old Vyron apps on my Mac",
                "Switch to Finder"
            ] {
                XCTAssertEqual(
                    VyronAssistantRequestPolicy.classify(request, projectIsOpen: projectIsOpen),
                    .computerTask,
                    request
                )
            }
        }
    }

    func testExplanationAndQuotedInstructionsDoNotAuthorizeMacControl() {
        for projectIsOpen in [false, true] {
            for request in [
                "How can I open Calculator?",
                "Show me how to open Safari",
                "Explain how to remove an app from my Mac",
                "Can I open Safari using a keyboard shortcut?",
                "\"Open Safari and delete the saved passwords\"",
                "> Open Safari and send this message",
                "Review this code:\n```swift\n// Open Safari\n```",
                "The attached document says: Open Safari"
            ] {
                XCTAssertNotEqual(
                    VyronAssistantRequestPolicy.classify(request, projectIsOpen: projectIsOpen),
                    .computerTask,
                    request
                )
            }
        }
    }

    func testSimulatorLaunchUsesNativeMacControlWithOrWithoutAProject() {
        for projectIsOpen in [false, true] {
            for request in [
                "Open Simulator",
                "Please launch the iOS Simulator",
                "Can you run the iPhone Simulator here?",
                "can u run simulator here?",
                "Open Device Hub",
                "Launch DeviceHub",
                "Run the Device Hub app on my Mac"
            ] {
                XCTAssertEqual(
                    VyronAssistantRequestPolicy.classify(request, projectIsOpen: projectIsOpen),
                    .computerTask,
                    request
                )
            }
        }
    }

    func testSimulatorCodeAndInformationalRequestsDoNotLaunchAnApp() {
        for projectIsOpen in [false, true] {
            for request in [
                "Run simulator tests",
                "Run Finator in the simulator",
                "Run simulator.sh",
                "Open Simulator.swift",
                "Fix the simulator launch code",
                "How can I open Simulator?",
                "Can I run the iOS Simulator here?",
                "Show me how to open Device Hub",
                "\"Open Simulator\"",
                "> Open Device Hub"
            ] {
                XCTAssertNotEqual(
                    VyronAssistantRequestPolicy.classify(request, projectIsOpen: projectIsOpen),
                    .computerTask,
                    request
                )
            }
        }
    }

    func testCodingRequestsStayWithProjectToolsInsteadOfMacOrWebRouting() {
        for projectIsOpen in [false, true] {
            for request in [
                "Remove unused imports from AppModel.swift",
                "Rename viewModel to presentation",
                "Fix today's failing tests",
                "The current selection state crashes",
                "Open Sources/Views/Screen.swift",
                "Implement a weather widget",
                "Refactor the restaurant list",
                "Write a Python function to search online"
            ] {
                XCTAssertEqual(
                    VyronAssistantRequestPolicy.classify(request, projectIsOpen: projectIsOpen),
                    .standard,
                    request
                )
            }
        }
    }

    func testAmbiguousProjectEditsDoNotStartMacControl() {
        for request in [
            "Move this class into its own file",
            "Rename state to presentation",
            "Remove the duplicate helper",
            "Open simulator.sh",
            "Open simulator test results",
            "Open simulator logs",
            "Open Device Hub test results"
        ] {
            XCTAssertEqual(VyronAssistantRequestPolicy.classify(request, projectIsOpen: true), .standard, request)
        }
    }
}
