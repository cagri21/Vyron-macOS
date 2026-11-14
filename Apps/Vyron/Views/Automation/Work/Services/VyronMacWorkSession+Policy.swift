import Foundation
import VyronAutomation
import VyronCore

extension VyronMacWorkSession {
    func policy(
        _ call: DevelopmentToolCall, application: DesktopApplication, element: NativeElementInfo?
    ) -> AutomationDecision {
        let kind: String
        switch call.function.name {
        case VyronMacWorkTools.openApp:
            if application.processIdentifier <= 0, attachedApplicationURLs[application.id] != nil {
                return .review("Review opening this attached application before the agent continues.")
            }
            kind = application.processIdentifier > 0 ? "activate" : "launch"
        case VyronMacWorkTools.openProject: kind = "launch"
        case VyronMacWorkTools.click: kind = "click"
        case VyronMacWorkTools.typeText: kind = "typeText"
        case VyronMacWorkTools.pressKey: kind = "pressKey"
        default: return .refused("This native action is unavailable.")
        }
        return AutomationPolicy.evaluate(
            kind: kind, applicationID: application.bundleIdentifier ?? application.id, element: element,
            text: optionalString("text", in: call), key: optionalString("key", in: call), goal: context.goal
        )
    }

    func authorize(
        _ call: DevelopmentToolCall, application: DesktopApplication, element: NativeElementInfo?
    ) async throws -> Bool {
        try validateCurrent()
        let identity = try JSONEncoder().encode([
            call.function.name, application.id,
            [element?.role, element?.subrole, element?.title, element?.description]
                .compactMap { $0 }.joined(separator: "\n"),
            ["text", "key", "path"].compactMap { optionalString($0, in: call) }.joined(separator: "\n")
        ]).base64EncodedString()
        guard !declinedActions.contains(identity) else {
            throw VyronMacWorkError(
                message: "This native action was already declined. It was not requested or run again."
            )
        }
        switch policy(call, application: application, element: element) {
        case .automatic: return false
        case .refused(let reason): throw VyronMacWorkError(message: reason)
        case .review(let reason):
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var verified: [String: DevelopmentJSONValue] = [
                "application": .string(application.name), "application_id": .string(application.id),
                "reason": .string(reason), "request": .object(call.function.arguments)
            ]
            if call.function.name == VyronMacWorkTools.openApp {
                if let url = attachedApplicationURLs[application.id] {
                    verified["attached_application_path"] = .string(url.path)
                } else if let url = application.installationURL {
                    verified["application_path"] = .string(url.path)
                }
            }
            if let element {
                verified["native_target"] = .object([
                    "role": .string(element.role), "title": .string(element.title),
                    "description": .string(element.description)
                ])
            }
            let arguments = String(decoding: try encoder.encode(verified), as: UTF8.self)
            let approved = await dependencies.review(MCPActionReview(
                connectionName: VyronAppText.automationTitle, toolName: call.function.name, arguments: arguments
            ))
            try validateCurrent()
            guard approved else {
                declinedActions.insert(identity)
                throw VyronMacWorkError(message: "The native action was declined. No action was sent; do not retry "
                    + "it through another tool, launcher or a newly captured snapshot.")
            }
            return true
        }
    }
}
