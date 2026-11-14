import Foundation
import VyronCore

struct VyronSideChatCommand {
    static let name = VyronBuiltInComposerCommand.side.rawValue
    static let invocation = "/" + name

    let question: String

    init?(prompt: String) {
        let parts = prompt.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first?.lowercased() == Self.invocation else { return nil }
        question = parts.dropFirst().first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
