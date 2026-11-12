// Generated using SwiftGen by Resources/generate_resources.py. Do not edit.
import Foundation

enum VyronAutomationCenterText {
    static func cpuPercent(_ p1: Double) -> String {
        VyronResourceBundle.format(
            "automationCenterCpuPercent",
            fallback: "%.0f%%",
            arguments: [p1]
        )
    }
    static func detailLabel(_ p1: String) -> String {
        VyronResourceBundle.format(
            "automationCenterDetailLabel",
            fallback: "%@:",
            arguments: [p1]
        )
    }
    static func elementReference(_ p1: Int) -> String {
        VyronResourceBundle.format(
            "automationCenterElementReference",
            fallback: "[%ld]",
            arguments: [p1]
        )
    }
    static func proposalHeading(_ p1: String, _ p2: String) -> String {
        VyronResourceBundle.format(
            "automationCenterProposalHeading",
            fallback: "%@ · %@",
            arguments: [p1, p2]
        )
    }
    static var urlPlaceholder: String {
        VyronResourceBundle.string("automationCenterUrlPlaceholder", fallback: "https://example.com")
    }
}
