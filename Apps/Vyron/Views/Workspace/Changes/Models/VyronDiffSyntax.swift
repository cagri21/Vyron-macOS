import SwiftUI

@MainActor
enum VyronDiffSyntax {
    private static let maximumHighlightedLineBytes = 4_096
    private static let tokens = #/
        \/\* .*? (?: \*\/ | $) | \/\/ | \#
        | " (?: \\. | [^"\\] )* "?
        | ' (?: \\. | [^'\\] )* '?
        | ` (?: \\. | [^`\\] )* `?
        | [\p{L}_$@] [\p{L}\p{M}\p{N}_$]*
        | 0 (?: [xX][\da-fA-F_]+ | [bB][01_]+ | [oO][0-7_]+ )
        | \d[\d_]* (?: \.[\d_]+ )? (?: [eE][+-]?[\d_]+ )?
        /#
    private static let literals: Set<String> = ["true", "false", "nil", "null", "undefined", "True", "False", "None"]
    private static let declarationKeywords: Set<String> = ["let", "var", "const", "func", "function", "def"]

    static func highlight(_ code: String, filename: String, scheme: ColorScheme = .dark) -> AttributedString {
        guard code.utf8.count <= maximumHighlightedLineBytes,
            let language = VyronDiffSyntaxLanguage(filename: filename)
        else { return AttributedString(code) }

        var result = AttributedString()
        var end = code.startIndex
        var previousToken: Substring = ""
        for match in code.matches(of: tokens) {
            let token = match.output
            result += AttributedString(code[end..<match.range.lowerBound])
            if (language == .python && token == "#") || (language != .python && token == "//") {
                result += styled(code[match.range.lowerBound...], color: VyronDiffSyntaxRole.comment.color(for: scheme))
                return result
            }
            let next = code[match.range.upperBound...].first { !$0.isWhitespace }
            let role = role(token, language: language, previous: previousToken, next: next)
            result += styled(token, color: role?.color(for: scheme))
            end = match.range.upperBound
            previousToken = token
        }
        result += AttributedString(code[end...])
        return result
    }

    private static func role(
        _ token: Substring,
        language: VyronDiffSyntaxLanguage,
        previous: Substring,
        next: Character?
    ) -> VyronDiffSyntaxRole? {
        guard let first = token.first else { return nil }
        if token.hasPrefix("/*"), language != .python { return .comment }
        if first == "\"" || first == "'" || first == "`" || first.isNumber || literals.contains(String(token)) {
            return .literal
        }
        if language.keywords.contains(String(token)) { return .keyword }
        if first.isUppercase || first == "@" { return .type }
        let isName = first.isLetter || first == "_"
        if isName, next == "(" || next == ":" || declarationKeywords.contains(String(previous)) {
            return .name
        }
        return nil
    }

    private static func styled(_ token: Substring, color: Color?) -> AttributedString {
        var text = AttributedString(token)
        text.foregroundColor = color
        return text
    }
}
