import Foundation

enum VyronSkillSetupIntent {
    private static let requestPrefixes: Set<String> = [
        "please", "kindly", "can", "could", "would", "will", "you", "help", "me", "to", "i", "want", "need", "like"
    ]
    private static let negations: Set<String> = [
        "not", "never", "don", "dont", "without", "yapma", "oluşturma", "створюй", "не"
    ]
    static func matches(_ prompt: String, entry: VyronSkillSetupCatalogEntry) -> Bool {
        let clause = prompt.split(whereSeparator: { $0 == ";" || $0 == "\n" }).first.map(String.init) ?? ""
        let trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("`"), !trimmed.hasPrefix(">"), !trimmed.hasPrefix("\"") else { return false }
        let words = tokens(trimmed)
        guard !words.isEmpty,
            let actionIndex = words.firstIndex(where: { word in entry.actions.contains(word) }),
            entry.terms.contains(where: { containsPhrase($0, in: words) })
        else { return false }
        let prefix = words[..<actionIndex]
        guard !prefix.contains(where: negations.contains) else { return false }
        if prefix.contains("i"), !prefix.contains(where: { ["want", "need", "like"].contains($0) }) {
            return false
        }
        let action = words[actionIndex]
        // English requests use an imperative or a short polite prefix. Turkish commonly puts its verb last.
        return prefix.allSatisfy(requestPrefixes.contains)
            || action.unicodeScalars.contains { !$0.isASCII }
    }

    private static func containsPhrase(_ phrase: String, in words: [String]) -> Bool {
        let expected = tokens(phrase).map(singular)
        guard !expected.isEmpty, expected.count <= words.count else { return false }
        let normalized = words.map(singular)
        return (0...(words.count - expected.count)).contains { index in
            Array(normalized[index..<(index + expected.count)]) == expected
        }
    }

    private static func tokens(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func singular(_ word: String) -> String {
        word.count > 3 && word.hasSuffix("s") ? String(word.dropLast()) : word
    }
}
