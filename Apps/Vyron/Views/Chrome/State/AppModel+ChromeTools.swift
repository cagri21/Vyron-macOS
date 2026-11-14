import Foundation
import VyronAutomation
import VyronCore

extension AppModel {
    func executeChromeTool(
        _ call: DevelopmentToolCall, context: VyronChromeToolContext
    ) async throws -> DevelopmentExternalResult {
        try validateChromeResponse(context)
        guard !isRunningScheduledTask else {
            return chromeToolFailure("Chrome tools require an interactive Work conversation.")
        }
        do {
            if call.function.name == VyronChromeTools.sessions {
                guard call.function.arguments.isEmpty else { return chromeToolFailure("Unexpected arguments.") }
                let sessions = try await chromeBridge.sessions()
                try validateChromeResponse(context)
                let data = try JSONEncoder().encode(sessions.map {
                    ["session_id": $0.id.uuidString, "extension_id": $0.extensionID]
                })
                return DevelopmentExternalResult(text: String(decoding: data, as: UTF8.self))
            }
            let arguments = call.function.arguments
            guard case .string(let sessionValue) = arguments["session_id"],
                let sessionID = UUID(uuidString: sessionValue)
            else { return chromeToolFailure("Use a session_id returned by vyron_chrome_sessions.") }
            let request = try chromeRequest(call, allowsActions: context.allowsActions)
            try validateChromeResponse(context)
            let result = try await chromeBridge.send(request, to: sessionID)
            try validateChromeResponse(context)
            return DevelopmentExternalResult(text: try result.encodedJSON(), isError: !result.ok)
        } catch is CancellationError {
            throw CancellationError()
        } catch VyronChromeBridgeError.hostUpdateRequired {
            return chromeToolFailure(VyronChromeText.hostUpdateRequired)
        } catch {
            return chromeToolFailure(error.localizedDescription)
        }
    }

    private func validateChromeResponse(_ context: VyronChromeToolContext) throws {
        guard ownsInteractiveWorkResponse(context.response) else { throw CancellationError() }
    }

    private func chromeRequest(
        _ call: DevelopmentToolCall, allowsActions: Bool
    ) throws -> VyronChromeBridgeRequest {
        let values = call.function.arguments
        if call.function.name == VyronChromeTools.tabs {
            guard Set(values.keys) == ["session_id"] else { throw chromeArgumentError() }
            return VyronChromeBridgeRequest(method: "tabs")
        }
        if call.function.name == VyronChromeTools.openTabs {
            return try chromeOpenTabsRequest(values, allowsActions: allowsActions)
        }
        guard let tabID = chromeInteger(values["tab_id"]) else { throw chromeArgumentError() }
        var arguments = VyronChromeBridgeArguments()
        arguments.tabID = tabID
        if call.function.name == VyronChromeTools.snapshot {
            guard Set(values.keys) == ["session_id", "tab_id"] else { throw chromeArgumentError() }
            return VyronChromeBridgeRequest(method: "snapshot", arguments: arguments)
        }
        guard call.function.name == VyronChromeTools.action, allowsActions,
            case .string(let action) = values["action"],
            ["click", "fill", "navigate", "reload"].contains(action),
            case .string(let snapshot) = values["snapshot_id"], UUID(uuidString: snapshot) != nil
        else { throw chromeArgumentError() }
        arguments.snapshotID = snapshot
        var expected: Set<String> = ["session_id", "tab_id", "snapshot_id", "action"]
        if action == "click" || action == "fill" {
            guard let elementID = chromeInteger(values["element_id"]) else { throw chromeArgumentError() }
            arguments.elementID = elementID
            expected.insert("element_id")
        }
        if action == "fill" {
            guard case .string(let text) = values["text"], !text.isEmpty,
                text.utf8.count <= 8_000, !text.contains("\0") else { throw chromeArgumentError() }
            arguments.text = text
            expected.insert("text")
        }
        if action == "navigate" {
            guard case .string(let url) = values["url"], let parsed = URLComponents(string: url),
                ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
                parsed.host?.isEmpty == false, parsed.user == nil, parsed.password == nil,
                url.utf8.count <= 8_192 else { throw chromeArgumentError() }
            arguments.url = url
            expected.insert("url")
        }
        guard Set(values.keys) == expected else { throw chromeArgumentError() }
        return VyronChromeBridgeRequest(method: action, arguments: arguments)
    }

    private func chromeOpenTabsRequest(
        _ values: [String: DevelopmentJSONValue], allowsActions: Bool
    ) throws -> VyronChromeBridgeRequest {
        guard allowsActions, Set(values.keys) == ["session_id", "urls", "group_title"],
            case .array(let destinations) = values["urls"],
            case .string(let title) = values["group_title"],
            (1...VyronChromeBridgeRequest.maximumOpenTabCount).contains(destinations.count)
        else { throw chromeArgumentError() }
        let urls = try destinations.map { destination in
            guard case .string(let url) = destination else { throw chromeArgumentError() }
            return url
        }
        return try VyronChromeBridgeRequest.openTabs(urls: urls, groupTitle: title)
    }

    private func chromeInteger(_ value: DevelopmentJSONValue?) -> Int? {
        guard case .number(let number) = value, number.isFinite, number.rounded() == number,
            number > 0, number <= Double(Int32.max) else { return nil }
        return Int(number)
    }

    private func chromeArgumentError() -> VyronChromeToolError { .invalidArguments }

    private func chromeToolFailure(_ message: String) -> DevelopmentExternalResult {
        DevelopmentExternalResult(text: message, isError: true)
    }
}
