import Foundation

extension AppModel {
    /// Only explicit local chat links in this user request authorize including another transcript.
    func linkedChatReferenceIDs(in prompt: String, excludingConversationID: UUID? = nil) -> [UUID] {
        let excludedID = excludingConversationID ?? selectedConversationID
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "()<>[]\"'`"))
        let sentencePunctuation = CharacterSet(charactersIn: ".,;:!")
        for token in prompt.components(separatedBy: separators) {
            let address = token.trimmingCharacters(in: sentencePunctuation)
            guard let url = URL(string: address), let link = VyronChatDeepLink(url: url),
                link.conversationID != excludedID,
                conversations.contains(where: { $0.id == link.conversationID }) else { continue }
            return [link.conversationID]
        }
        return []
    }

    func linkedChatReferenceContext(in prompt: String, excludingConversationID: UUID? = nil) -> String? {
        let references = linkedChatReferenceIDs(in: prompt, excludingConversationID: excludingConversationID)
            .compactMap { id -> String? in
                guard let source = conversations.first(where: { $0.id == id }) else { return nil }
                return VyronConversationRequestContext.bytePrefix(
                    VyronChatHandoffContext.reference(for: source), limit: 3_600
                )
            }
        guard !references.isEmpty else { return nil }
        return references.joined(separator: "\n\n")
    }
}
