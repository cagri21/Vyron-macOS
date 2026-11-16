import Foundation

public struct NativeElementInfo: Sendable, Equatable {
    public let elementID: Int
    public let applicationID: String
    public let role: String
    public let subrole: String
    public let title: String
    public let description: String
    public let value: String
    public let actions: [String]
    public let isSecure: Bool
    public let url: URL?

    public init(
        elementID: Int,
        applicationID: String,
        role: String,
        subrole: String = "",
        title: String,
        description: String,
        value: String,
        actions: [String],
        isSecure: Bool = false,
        url: URL? = nil
    ) {
        self.elementID = elementID
        self.applicationID = applicationID
        self.role = role
        self.subrole = subrole
        self.title = title
        self.description = description
        self.value = value
        self.actions = actions
        self.isSecure = isSecure
        self.url = url
    }
}

public enum AutomationDecision: Sendable, Equatable {
    case automatic(String)
    case review(String)
    case refused(String)
}

/// A deterministic execution gate. Element labels must come from MacController,
/// never from an AI proposal or from text copied out of the inspected page.
public enum AutomationPolicy {
    private static let terminalIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty", "co.zeit.hyper"
    ]
    private static let browserIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
        "com.google.Chrome.canary", "org.chromium.Chromium", "org.mozilla.firefox",
        "org.mozilla.nightly", "com.brave.Browser", "com.brave.Browser.beta",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "company.thebrowser.Browser",
        "company.thebrowser.dia", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS", "com.duckduckgo.macos.browser"
    ]
    static let automaticLaunchApplicationIDs: Set<String> = browserIDs.union([
        "com.apple.calculator", "com.apple.TextEdit", "com.apple.Notes", "com.apple.dt.Xcode",
        "com.figma.Desktop", "com.microsoft.Outlook", "com.apple.mail", "com.apple.systempreferences"
    ]).union(VyronXcodeApplicationCatalog.applicationIDs)
    private static let automaticSystemApplicationPaths = [
        "com.apple.Photos": "/System/Applications/Photos.app",
        "com.apple.Preview": "/System/Applications/Preview.app",
        "com.apple.QuickTimePlayerX": "/System/Applications/QuickTime Player.app"
    ]
    private static let benignNavigation: Set<String> = [
        "back", "forward", "go back", "go forward", "previous", "home",
        "search", "find", "find next", "find previous", "refresh", "reload",
        "show sidebar", "hide sidebar", "show more", "show less"
    ]
    private static let calculatorLabels: Set<String> = [
        "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", ".", ",", "+", "−", "-", "×", "*", "÷", "/", "=", "%", "+/−",
        "+/-",
        "add", "plus", "subtract", "minus", "multiply", "times", "divide", "equals", "equal",
        "decimal", "decimal separator", "percent", "percentage", "change sign", "negate", "clear", "all clear", "ac",
        "c"
    ]
    private static let sensitivePattern =
        #"\b(send|post|publish|submit|pay|payment|buy|purchase|checkout|delete|erase|trash|remove|reset|install|uninstall|permission|permissions|allow|approve|accept|agree|terms|login|logout|sign\s*in|sign\s*out|log\s*in|log\s*out|security|password|passkey|credential|credentials|authorize|authenticate|authentication|transfer|download|upload|save|share|unsubscribe)\b"#

    public static func evaluateLaunch(of application: DesktopApplication) -> AutomationDecision {
        launchDecision(
            applicationID: application.bundleIdentifier ?? application.id,
            installationURL: application.installationURL
        )
    }

    private static func launchDecision(applicationID: String, installationURL: URL? = nil) -> AutomationDecision {
        guard !applicationID.isEmpty else { return .refused("A specific installed application is required.") }
        let isKnownSystemBundle = if let installationURL, installationURL.isFileURL,
            let expectedPath = automaticSystemApplicationPaths[applicationID] {
            installationURL.standardizedFileURL.path == expectedPath
        } else {
            false
        }
        return automaticLaunchApplicationIDs.contains(applicationID) || isKnownSystemBundle
            ? .automatic("Open a known installed application.")
            : .review("Review opening this application before the agent continues.")
    }

    public static func evaluate(
        kind: String,
        applicationID: String,
        element: NativeElementInfo? = nil,
        text: String? = nil,
        key: String? = nil,
        url: URL? = nil,
        goal: String,
        approvedOrigins: Set<String> = []
    ) -> AutomationDecision {
        let action = kind.lowercased()
        guard !applicationID.isEmpty else { return .refused("A specific installed application is required.") }
        if let element, element.applicationID != applicationID {
            return .refused("The native element belongs to a different application.")
        }
        if let element,
            element.isSecure || element.role.lowercased().contains("secure")
                || element.subrole.lowercased().contains("secure") {
            return .refused("Secure fields cannot be read or controlled.")
        }
        if terminalIDs.contains(applicationID), ["typetext", "presskey"].contains(action) {
            return .refused("Terminal text and keyboard control are disabled.")
        }
        switch action {
        case "inspect", "focus", "activate", "wait", "complete":
            return .automatic("Read-only inspection or routine application focus.")
        case "launch":
            return launchDecision(applicationID: applicationID)
        case "openurl":
            guard browserIDs.contains(applicationID) else {
                return .refused("Web addresses require a supported browser.")
            }
            guard let url, let origin = origin(for: url), !hasCommandQuery(url) else {
                return .refused(
                    "Only ordinary HTTP or HTTPS addresses without credentials or command parameters are allowed."
                )
            }
            if sensitiveURL(url) {
                return .review("This address may perform an account, publishing, payment or destructive action.")
            }
            let approved = Set(approvedOrigins.compactMap { URL(string: $0).flatMap { self.origin(for: $0) } })
            guard approved.contains(origin) || explicitOrigins(in: goal).contains(origin) else {
                return .review("Opening a new website requires your approval.")
            }
            return .automatic("The website origin was explicitly requested or already approved.")
        case "click":
            guard let element, element.actions.contains("click") else {
                return .review("No verified native clickable element is available.")
            }
            let labels = nativeLabels(element, includeValue: true)
            guard !labels.isEmpty else { return .review("An unlabeled control requires your review.") }
            if labels.contains(where: sensitive) {
                return .review("This control may send data, change an account, make a purchase or remove content.")
            }
            if let decision = VyronXcodeMenuPolicy.evaluate(element: element, labels: labels, goal: goal) {
                return decision
            }
            if element.role == "AXLink", browserIDs.contains(applicationID), let href = element.url {
                guard origin(for: href) != nil, !hasCommandQuery(href) else {
                    return .refused("This native link is not an ordinary credential-free web address.")
                }
                guard !sensitiveURL(href) else {
                    return .review("This native link may change an account, send sensitive data or remove content.")
                }
                return .automatic("Follow a verified native browser hyperlink.")
            }
            if applicationID == "com.apple.calculator", element.role == "AXButton",
                labels.allSatisfy({ calculatorLabels.contains($0) }) {
                return .automatic("Use a verified Calculator number or arithmetic control.")
            }
            guard labels.allSatisfy({ benignNavigation.contains($0) }) else {
                return .review("This native control is outside routine navigation.")
            }
            return .automatic("Use an exactly recognized native navigation or search control.")
        case "typetext":
            guard let element, element.actions.contains("typeText"),
                ["AXTextField", "AXSearchField", "AXComboBox"].contains(element.role)
            else {
                return .review("Text entry requires a verified native search or address field.")
            }
            if nativeLabels(element, includeValue: false).contains(where: sensitive) {
                return .review("Text entry in this account or security field needs your review.")
            }
            guard isSearchField(element) else {
                return .review("Review text entry outside a recognized search or address field.")
            }
            guard let text, !text.isEmpty,
                text.count <= VyronAutomationTextEntryLimits.maximumAutomaticTextCharacters,
                !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                goal.range(of: text, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            else {
                return .review(
                    "Automatic search text must be copied literally from your own task, rather than from app content."
                )
            }
            return .automatic("Place text from your request into a verified native search or address field.")
        case "presskey":
            let normalized = (key ?? "").lowercased()
            if ["back", "forward", "reload"].contains(normalized) {
                return browserIDs.contains(applicationID)
                    ? .automatic("Routine browser navigation.")
                    : .refused("Browser navigation requires a supported browser.")
            }
            if ["up", "down", "left", "right", "arrowup", "arrowdown", "arrowleft", "arrowright", "tab", "escape"]
                .contains(normalized) {
                return .automatic("Routine focus or navigation key; the native controller rechecks the target.")
            }
            if ["return", "enter", "space"].contains(normalized) {
                // The API has no proof that a supplied element is the current keyboard focus.
                return .review("Return and Space can submit or activate a control. Review this step.")
            }
            return .refused("This keyboard shortcut is not supported.")
        default:
            return .refused("This action is not supported by the native controller.")
        }
    }

    public static func origin(for url: URL) -> String? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
            let host = parts.host?.lowercased(), !host.isEmpty,
            parts.user == nil, parts.password == nil,
            parts.port == nil || (1...65_535).contains(parts.port!),
            url.absoluteString.utf8.count <= 8_192,
            !url.absoluteString.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        let defaultPort = scheme == "https" ? 443 : 80
        let port = parts.port.flatMap { $0 == defaultPort ? nil : ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    public static func explicitOrigins(in goal: String) -> Set<String> {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(goal.startIndex..<goal.endIndex, in: goal)
        return Set(detector.matches(in: goal, range: range).compactMap { $0.url.flatMap { origin(for: $0) } })
    }

    private static func nativeLabels(_ element: NativeElementInfo, includeValue: Bool) -> [String] {
        let values = [element.title, element.description] + (includeValue ? [element.value] : [])
        return Array(Set(values.map(normalize).filter { !$0.isEmpty }))
    }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func isSearchField(_ element: NativeElementInfo) -> Bool {
        if element.role == "AXSearchField" || element.subrole == "AXSearchField" { return true }
        let labels = nativeLabels(element, includeValue: false)
        return labels.contains {
            $0.range(
                of:
                    #"\A(search|find)(\b|\s)|\A(address|address and search|smart search)(\s+(bar|field))?\z|\A(search or enter (website|address|url))\z"#,
                options: .regularExpression
            ) != nil
        }
    }

    private static func sensitive(_ text: String) -> Bool {
        text.range(of: sensitivePattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func hasCommandQuery(_ url: URL) -> Bool {
        let names: Set<String> = ["cmd", "command", "exec", "execute", "shell", "script"]
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains {
            names.contains($0.name.lowercased())
        } ?? false
    }

    private static func sensitiveURL(_ url: URL) -> Bool {
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = parts?.path ?? url.path
        let query = parts?.queryItems?.map { "\($0.name) \($0.value ?? "")" }.joined(separator: " ") ?? ""
        let fragment = parts?.fragment ?? ""
        if sensitive(path + " " + query + " " + fragment) { return true }
        let secretNames: Set<String> = [
            "token", "access_token", "auth", "authorization", "api_key", "apikey", "password", "passwd", "secret",
            "session", "sessionid", "code"
        ]
        if parts?.queryItems?.contains(where: { secretNames.contains($0.name.lowercased()) }) == true { return true }
        return fragment.range(
            of: #"\b(token|access_token|secret|session|api_key|password)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}
