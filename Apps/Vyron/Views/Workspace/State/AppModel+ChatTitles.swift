import Foundation

extension AppModel {
    func initialConversationTitle(for prompt: String) -> String {
        let maximumCharacters = 54
        guard let id = linkedChatReferenceIDs(in: prompt).first,
            let source = conversations.first(where: { $0.id == id }),
            let link = VyronChatDeepLink(conversationID: id).url?.absoluteString
        else { return String(prompt.replacingOccurrences(of: "\n", with: " ").prefix(maximumCharacters)) }
        // Omit other local chat addresses from the display title too; only the resolved ID above supplies its subject.
        let addressPrefix = String(link.dropLast(id.uuidString.count))
        let addressPattern = NSRegularExpression.escapedPattern(for: addressPrefix) + "[^\\s()<>\\[\\]\"'`]+"
        let markdownLink = "\\[[^\\]\\r\\n]*\\]\\(\\s*<?" + addressPattern + ">?\\s*\\)"
        let withoutMarkdownLink = prompt.replacingOccurrences(
            of: markdownLink, with: "", options: [.regularExpression, .caseInsensitive]
        )
        let request = singleLineChatTitle(withoutMarkdownLink.replacingOccurrences(
            of: addressPattern, with: "", options: [.regularExpression, .caseInsensitive]
        )).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "()<>[].,:;!?`")))
        let sourceTitle = singleLineChatTitle(source.title)
        guard !request.isEmpty else { return String(sourceTitle.prefix(maximumCharacters)) }
        guard !sourceTitle.isEmpty else { return String(request.prefix(maximumCharacters)) }
        // Reserve space for both the referenced subject and the user's request.
        let requestBudget = min(request.count, maximumCharacters / 2)
        let sourceBudget = maximumCharacters - requestBudget - 3
        return shortenedChatTitle(sourceTitle, limit: sourceBudget) + " · "
            + shortenedChatTitle(request, limit: requestBudget)
    }

    private func singleLineChatTitle(_ text: String) -> String {
        text.components(separatedBy: .controlCharacters).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func shortenedChatTitle(_ text: String, limit: Int) -> String {
        text.count <= limit ? text : String(text.prefix(limit - 1)) + "…"
    }
}
