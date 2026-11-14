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

    static func highlight(_ code: String, filename: String) -> AttributedString {
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
                result += styled(code[match.range.lowerBound...], color: Palette.diffSyntaxComment)
                return result
            }
            let next = code[match.range.upperBound...].first { !$0.isWhitespace }
            result += styled(token, color: color(token, language: language, previous: previousToken, next: next))
            end = match.range.upperBound
            previousToken = token
        }
        result += AttributedString(code[end...])
        return result
    }

    private static func color(
        _ token: Substring,
        language: VyronDiffSyntaxLanguage,
        previous: Substring,
        next: Character?
    ) -> Color? {
        guard let first = token.first else { return nil }
        if token.hasPrefix("/*"), language != .python { return Palette.diffSyntaxComment }
        if first == "\"" || first == "'" || first == "`" || first.isNumber || literals.contains(String(token)) {
            return Palette.diffSyntaxLiteral
        }
        if language.keywords.contains(String(token)) { return Palette.diffSyntaxKeyword }
        if first.isUppercase || first == "@" { return Palette.diffSyntaxType }
        let isName = first.isLetter || first == "_"
        if isName, next == "(" || next == ":" || declarationKeywords.contains(String(previous)) {
            return Palette.diffSyntaxName
        }
        return nil
    }

    private static func styled(_ token: Substring, color: Color?) -> AttributedString {
        var text = AttributedString(token)
        text.foregroundColor = color
        return text
    }
}
