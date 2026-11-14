import Foundation

struct VyronDiffSourceLine: Equatable, Sendable {
    let text: String
    let endsWithNewline: Bool

    static func split(_ text: String) -> [Self] {
        guard !text.isEmpty else { return [] }
        var lines = text.components(separatedBy: "\n")
        let endsWithNewline = text.utf8.last == 10
        if endsWithNewline { lines.removeLast() }
        return lines.enumerated().map { index, line in
            Self(text: line, endsWithNewline: index < lines.count - 1 || endsWithNewline)
        }
    }
}
