import Foundation

/// Recognizes only native Xcode menu labels whose operation is explicitly requested by the user.
enum VyronXcodeMenuPolicy {
    static func evaluate(element: NativeElementInfo, labels: [String], goal: String) -> AutomationDecision? {
        guard element.applicationID == VyronXcodeApplicationCatalog.xcodeID,
            ["AXMenuBarItem", "AXMenuItem"].contains(element.role),
            Set(labels).count == 1, let label = labels.first else { return nil }
        if ["product", "window"].contains(label) {
            return .automatic("Open an exactly recognized native Xcode navigation menu.")
        }
        guard element.role == "AXMenuItem", ["run", "build", "test", "stop"].contains(label),
            explicitlyRequests(label, in: goal) else { return nil }
        return .automatic("Use the exactly requested operation in Xcode's verified native menu.")
    }

    private static func explicitlyRequests(_ operation: String, in goal: String) -> Bool {
        let text = goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.contains("```"), !text.hasPrefix("\""), !text.hasPrefix(">"),
            !["how ", "show me how ", "tell me how ", "explain ", "can i ", "could i "]
                .contains(where: text.hasPrefix) else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: operation)
        let pattern = #"(?:\A|[.!?\n]\s*|\b(?:and|then)\s+)(?:(?:please|can you|could you|would you|can u)\s+)*"#
            + escaped + #"\b"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }
}
