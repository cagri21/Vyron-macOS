import Foundation

/// Recognizes announced execution represented as text, without decoding it into an executable call.
enum VyronOllamaPrintedToolAction {
    private static let maximumAnnouncementLines = 12

    static func detects(_ content: String, toolNames: Set<String>) -> Bool {
        var prose: [String] = []
        var body: [String] = []
        var fence: String?
        var isAction = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let current = fence {
                if trimmed.hasPrefix(current), trimmed.dropFirst(current.count).allSatisfy(\.isWhitespace) {
                    if isAction, containsToolObject(body.joined(separator: "\n"), toolNames: toolNames) { return true }
                    fence = nil
                    body.removeAll(keepingCapacity: true)
                    prose.removeAll(keepingCapacity: true)
                } else {
                    body.append(line)
                }
                continue
            }
            guard let marker = trimmed.first, marker == "`" || marker == "~" else {
                prose.append(line)
                continue
            }
            let length = trimmed.prefix(while: { $0 == marker }).count
            guard length >= 3 else { prose.append(line); continue }
            fence = String(repeating: String(marker), count: length)
            let language = trimmed.dropFirst(length).trimmingCharacters(in: .whitespaces).lowercased()
            isAction = ["", "json", "jsonc"].contains(language)
                && announcesExecution(prose.suffix(maximumAnnouncementLines).joined(separator: "\n"))
        }
        return false
    }

    private static func announcesExecution(_ prose: String) -> Bool {
        let text = prose.replacingOccurrences(of: "**", with: "")
        let example = #"(?i)\b(example|sample|tutorial|illustrat\w*|hypothetical|would|could)\b|\b(?:not|never)\s+execut(?:ed|ing)\b"#
        guard text.range(of: example, options: .regularExpression) == nil else { return false }
        let announcement = #"(?im)^\s*(?:[-*]\s+|#{1,6}\s*)?(?:(?:action\s+summary|next\s+action)\s*:\s*)?(?:I(?:'m|’m|\s+am)\s+)?(?:now\s+)?(?:executing|running|calling|invoking)\b"#
        return text.range(of: announcement, options: .regularExpression) != nil
    }

    private static func containsToolObject(_ text: String, toolNames: Set<String>) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return false }
        return toolNames.contains { name in
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let pattern = #""(?:tool|name)"\s*:\s*""# + escaped + #"""#
            return trimmed.range(of: pattern, options: .regularExpression) != nil
        }
    }
}
