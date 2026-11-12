import Foundation

/// Recognizes an explicit navigation request, never authorization to run the destination task.
struct VyronChatHandoffIntent {
    let request: String
    let projectPath: String?
    let movesConversation: Bool

    private static let boundary = #"(?:^|[.!?;\n]|\s{2,}|\band\s+)\s*"#
    private static let courtesy = #"(?:(?:please|can you|could you|would you|i want you to|i need you to)\s+)?"#
    private static let conversationMovePatterns = [
        boundary + courtesy + #"move\s+(?:this|the current|our current)\s+(?:chat|conversation)"#
            + #"(?:\s+and\s+(?:its|the)\s+context)?\s+(?:to|into)\s+(?:the\s+)?(?<destination>[^\n!?;]+)"#,
        boundary + #"(?:lutfen\s+)?bu\s+(?:sohbeti|konusmayi)\s+"#
            + #"(?<destination>[^\n.!?;]+?)\s+tasi(?=\s|[.!?;]|$)"#,
        boundary + normalized(#"(?:будь ласка[ ,]+)?перенеси\s+(?:цей чат|цю розмову)\s+(?:до|у|в)\s+"#)
            + #"(?<destination>[^\n.!?;]+)"#
    ]

    init?(prompt: String, projects: [String: String]) {
        let request = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty,
            request.count <= VyronChatHandoffContext.maximumRequestCharacters,
            request.utf8.count <= VyronConversationLimits.maximumMessageBytes
        else { return nil }
        let normalized = Self.normalized(request)
        let searchable = Self.maskedReferenceText(normalized)
        let move = Self.destination(in: searchable, original: normalized, patterns: Self.conversationMovePatterns)
        guard let destination = move ?? Self.handoffDestination(in: searchable, original: normalized) else { return nil }
        let matches = projects.compactMap { path, name in
            Self.matchesDestination(destination, name: name, path: path) ? path : nil
        }
        let uniqueMatches = Set(matches)
        guard !uniqueMatches.isEmpty || Self.namesProject(destination) else { return nil }
        self.request = request
        projectPath = uniqueMatches.count == 1 ? uniqueMatches.first : nil
        movesConversation = move != nil
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
    }

    private static func handoffDestination(in searchable: String, original: String) -> String? {
        let object = #"(?:this|the current|our current)\s+(?:request|task|chat|conversation|discussion)"#
        let context = #"(?:\s+and\s+(?:its|the)\s+context)?"#
        let patterns = [
            boundary + courtesy + #"(?:move|send|transfer|handoff|hand\s+off)\s+"# + object + context
                + #"\s+(?:to|into)\s+(?:the\s+)?(?<destination>[^\n!?;]+)"#,
            boundary + courtesy + #"hand\s+"# + object + #"\s+off\s+to\s+(?:the\s+)?(?<destination>[^\n!?;]+)"#,
            boundary + courtesy + #"continue\s+"# + object + context
                + #"\s+(?:in|to|within)\s+(?:the\s+)?(?<destination>[^\n!?;]+)"#,
            boundary + #"(?:lutfen\s+)?bu\s+(?:istegi|gorevi|sohbeti|konusmayi)\s+"#
                + #"(?<destination>[^\n.!?;]+?)\s+(?:tasi|gonder|aktar)(?=\s|[.!?;]|$)"#,
            boundary + normalized(#"(?:будь ласка[ ,]+)?(?:перенеси|передай|надішли)\s+"#)
                + normalized(#"(?:цей запит|це завдання|цей чат|цю розмову)\s+(?:до|у|в)\s+"#)
                + #"(?<destination>[^\n.!?;]+)"#
        ]
        return destination(in: searchable, original: original, patterns: patterns)
    }

    private static func destination(in searchable: String, original: String, patterns: [String]) -> String? {
        let fullRange = NSRange(searchable.startIndex..., in: searchable)
        for pattern in patterns {
            guard let expression = expression(pattern),
                let match = expression.firstMatch(in: searchable, range: fullRange)
            else { continue }
            let range = match.range(withName: "destination")
            guard range.location != NSNotFound,
                let originalRange = Range(range, in: original)
            else { continue }
            return String(original[originalRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func matchesDestination(_ destination: String, name: String, path: String) -> Bool {
        let text = destination.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "\"'“”‘’`")
        ))
        let candidates = Set([name, path, URL(fileURLWithPath: path).lastPathComponent])
        return candidates.contains { candidate in
            let normalizedName = normalized(candidate).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedName.isEmpty else { return false }
            let components = normalizedName.components(separatedBy: CharacterSet(charactersIn: " -_"))
                .filter { !$0.isEmpty }
            let namePattern = components.map(NSRegularExpression.escapedPattern(for:)).joined(separator: #"[\s_-]+"#)
            let prefix = #"^(?:(?:project|folder|проєкт|проект)\s+)?"#
            let suffix = #"(?=$|[.,!?;"'“”‘’`]|\s+(?:project|folder|projesine|klasorune|and|so|it|where|with|then|to|please)\b)"#
            return text.range(of: prefix + namePattern + suffix, options: .regularExpression) != nil
        }
    }

    private static func namesProject(_ destination: String) -> Bool {
        let patterns = [
            #"^(?:another|a different|the other|a new)\s+project\b"#,
            #"^(?:project|folder|проєкт|проект)\s+\S"#,
            #"^.{1,100}?\s+(?:project|folder|projesine|klasorune|проєкту|проекту)(?=\s|[.!?;]|$)"#
        ]
        return patterns.contains { destination.range(of: $0, options: .regularExpression) != nil }
    }

    private static func maskedReferenceText(_ text: String) -> String {
        let result = NSMutableString(string: text)
        let patterns = [
            #"(?ms)^\s*```.*?(?:^\s*```[^\n]*(?:\n|$)|\z)"#,
            #"(?ms)^\s*~~~.*?(?:^\s*~~~[^\n]*(?:\n|$)|\z)"#,
            #"(?m)^\s*>[^\n]*"#
        ]
        for pattern in patterns {
            guard let expression = expression(pattern) else { return String(repeating: " ", count: result.length) }
            let matches = expression.matches(in: result as String, range: NSRange(location: 0, length: result.length))
            for match in matches.reversed() {
                result.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
            }
        }
        let quoted = #"`[^`\n]*`|"[^"\n]*"|“[^”\n]*”|‘[^’\n]*’|(?<![\p{L}\p{N}])'[^'\n]*'(?![\p{L}\p{N}])"#
        guard let expression = expression(quoted) else { return String(repeating: " ", count: result.length) }
        let matches = expression.matches(in: result as String, range: NSRange(location: 0, length: result.length))
        for match in matches.reversed() {
            let excerpt = result.substring(with: match.range)
            let directions = #"\b(?:move|send|transfer|handoff|hand|continue)\s+(?:this|the current|our current)\b"#
            let otherLanguages = #"\b(?:bu\s+(?:istegi|gorevi|sohbeti|konusmayi)|перенеси|передай|надішли)\b"#
            guard excerpt.range(of: directions, options: .regularExpression) != nil
                || excerpt.range(of: normalized(otherLanguages), options: .regularExpression) != nil
            else { continue }
            result.replaceCharacters(in: match.range, with: String(repeating: " ", count: match.range.length))
        }
        return result as String
    }

    private static func expression(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            assertionFailure("A built-in chat handoff pattern is invalid.")
            return nil
        }
    }
}
