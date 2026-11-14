import Foundation
import VyronCore

struct VyronConversationCompactionCommand {
    static let name = VyronBuiltInComposerCommand.compact.rawValue
    static let invocation = "/" + name
    static let maximumFocusBytes = 1_500

    let focus: String

    init?(prompt: String) {
        let parts = prompt.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard parts.first?.lowercased() == Self.invocation else { return nil }
        focus = parts.count == 2 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Administrative compaction turns must not replace a development task's original goal or checkpoint lineage.
    static func taskHistory(_ messages: [ChatMessage]) -> [ChatMessage] {
        var isCompactionTurn = false
        return messages.filter { message in
            if message.conversationRole == .user { isCompactionTurn = Self(prompt: message.content) != nil }
            return !isCompactionTurn
        }
    }
}
