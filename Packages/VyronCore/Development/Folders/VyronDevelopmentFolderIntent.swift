import Foundation

enum VyronDevelopmentFolderIntent {
    static func isLookup(_ goal: String) -> Bool {
        let request = normalized(goal)
        return request.range(of: lookup, options: .regularExpression) != nil
            && request.range(of: folderAction, options: .regularExpression) == nil
    }

    static func isMoveRequest(_ goal: String) -> Bool {
        normalized(goal).range(of: courtesy + move, options: .regularExpression) != nil
    }

    private static func normalized(_ goal: String) -> String {
        goal.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static let courtesy =
        #"^(?:please[,\s]+|(?:can you|could you|would you|i (?:need|want) (?:you )?to|help me)\s+)*"#
    private static let lookup = courtesy + #"(?:find|search|look (?:for|up|in)|locate|read|list|inspect|check|show me)\b"#
    private static let move =
        #"(?:move\s+(?:this|the current|our current)\s+(?:chat|conversation)\s+(?:to|into)|switch to)\b"#
    private static let folderAction =
        #"(?:[.!?;\n]\s*|\b(?:and|then)\s+)(?:create|make|add|set up)\b"# + #"|\b"# + move
}
