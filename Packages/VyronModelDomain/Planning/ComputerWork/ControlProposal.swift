import Foundation

/// A reviewable description of one action. Decoding or validating this value never executes it.
public struct ControlProposal: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case inspect
        case launch
        case activate
        case openURL
        case click
        case typeText
        case pressKey
        case complete
        case wait
    }

    public static let allowedKeys: Set<String> = [
        "return", "escape", "tab", "space", "up", "down", "left", "right",
        "back", "forward", "reload"
    ]

    public static let browserApplicationIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.google.Chrome",
        "com.google.Chrome.canary", "org.chromium.Chromium", "org.mozilla.firefox",
        "org.mozilla.nightly", "com.brave.Browser", "com.brave.Browser.beta",
        "com.microsoft.edgemac", "com.microsoft.edgemac.Beta", "company.thebrowser.Browser",
        "company.thebrowser.dia", "com.operasoftware.Opera", "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS", "com.duckduckgo.macos.browser"
    ]

    private static let terminalApplicationIDs: Set<String> = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable", "net.kovidgoyal.kitty", "org.alacritty", "co.zeit.hyper"
    ]

    public let kind: Kind
    public let applicationID: String?
    public let elementID: Int?
    public let text: String?
    public let url: String?
    public let key: String?
    public let seconds: Int?
    public let explanation: String

    public init(
        kind: Kind,
        applicationID: String? = nil,
        elementID: Int? = nil,
        text: String? = nil,
        url: String? = nil,
        key: String? = nil,
        seconds: Int? = nil,
        explanation: String
    ) {
        self.kind = kind
        self.applicationID = applicationID
        self.elementID = elementID
        self.text = text
        self.url = url
        self.key = key
        self.seconds = seconds
        self.explanation = explanation
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, applicationID, elementID, text, url, key, seconds, explanation
    }

    private struct AnyKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.container(keyedBy: AnyKey.self)
        let allowed = Set(CodingKeys.allCases.map(\.rawValue))
        guard raw.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
            throw VyronControlProposalRejection.unsupportedFields.error
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(Kind.self, forKey: .kind)
        applicationID = try values.decodeIfPresent(String.self, forKey: .applicationID)
        elementID = try values.decodeIfPresent(Int.self, forKey: .elementID)
        text = try values.decodeIfPresent(String.self, forKey: .text)
        url = try values.decodeIfPresent(String.self, forKey: .url)
        key = try values.decodeIfPresent(String.self, forKey: .key)
        seconds = try values.decodeIfPresent(Int.self, forKey: .seconds)
        explanation = try values.decode(String.self, forKey: .explanation)
    }

    @discardableResult
    public func validated(
        expectedApplicationID: String? = nil,
        availableElementIDs: Set<Int>? = nil
    ) throws -> ControlProposal {
        guard let applicationID, Self.validApplicationID(applicationID) else {
            throw VyronControlProposalRejection.applicationRequired.error
        }
        if let expectedApplicationID, applicationID != expectedApplicationID {
            throw VyronControlProposalRejection.unexpectedApplication.error
        }
        let explanationText = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !explanationText.isEmpty,
            explanation.utf8.count <= VyronControlProposalLimits.maximumExplanationUTF8Bytes,
            !Self.hasUnsafeControls(explanation)
        else {
            throw VyronControlProposalRejection.explanationRequired.error
        }
        if let elementID {
            guard VyronControlProposalLimits.elementIDs.contains(elementID) else {
                throw VyronControlProposalRejection.elementOutsideSnapshot.error
            }
            if let availableElementIDs, !availableElementIDs.contains(elementID) {
                throw VyronControlProposalRejection.elementMissingFromSnapshot.error
            }
        }
        switch kind {
        case .inspect, .launch, .activate, .complete:
            guard elementID == nil, text == nil, url == nil, key == nil, seconds == nil else {
                throw VyronControlProposalRejection.applicationOnly.error
            }
        case .wait:
            guard let seconds, VyronControlProposalLimits.waitSeconds.contains(seconds),
                elementID == nil, text == nil, url == nil, key == nil
            else {
                throw VyronControlProposalRejection.invalidWait.error
            }
        case .openURL:
            guard Self.browserApplicationIDs.contains(applicationID), elementID == nil,
                text == nil, key == nil, seconds == nil, let url, Self.validWebURL(url)
            else {
                throw VyronControlProposalRejection.invalidWebURL.error
            }
        case .click:
            guard elementID != nil, text == nil, url == nil, key == nil, seconds == nil else {
                throw VyronControlProposalRejection.elementRequired.error
            }
        case .typeText:
            guard !Self.terminalApplicationIDs.contains(applicationID),
                elementID != nil, let text, !text.isEmpty,
                text.count <= VyronControlProposalLimits.maximumTypedTextCharacters,
                text.utf8.count <= VyronControlProposalLimits.maximumTypedTextUTF8Bytes,
                !Self.hasUnsafeControls(text),
                url == nil, key == nil, seconds == nil
            else {
                throw VyronControlProposalRejection.invalidTypedText.error
            }
        case .pressKey:
            guard !Self.terminalApplicationIDs.contains(applicationID),
                elementID == nil, text == nil, url == nil, seconds == nil,
                let key, Self.allowedKeys.contains(key)
            else {
                throw VyronControlProposalRejection.unsupportedNavigationKey.error
            }
            if ["back", "forward", "reload"].contains(key), !Self.browserApplicationIDs.contains(applicationID) {
                throw VyronControlProposalRejection.browserRequired.error
            }
        }
        return self
    }

    package static func validApplicationID(_ identifier: String) -> Bool {
        identifier.utf8.count <= VyronControlProposalLimits.maximumApplicationIDUTF8Bytes
            && identifier.range(
                of: #"\A[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+\z"#,
                options: .regularExpression
            ) != nil
    }

    package static func validWebURL(_ value: String) -> Bool {
        guard value.utf8.count <= VyronControlProposalLimits.maximumURLUTF8Bytes,
            !value.unicodeScalars.contains(where: {
                CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0)
            }),
            let parts = URLComponents(string: value),
            ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
            let host = parts.host, !host.isEmpty,
            parts.user == nil, parts.password == nil,
            parts.port == nil || (1...65_535).contains(parts.port!),
            parts.url != nil
        else { return false }
        return true
    }

    private static func hasUnsafeControls(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) && $0 != "\n" && $0 != "\t"
        }
    }
}
