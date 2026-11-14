import Foundation
import VyronModelDomain

struct VyronConversationTranscript {
    private static let legacyOptionCount = 2...3

    let rows: [VyronConversationTranscriptRow]

    init(messages: [ChatMessage]) {
        let ownership = VyronConversationResponseOwnership(messages: messages)
        var rows: [VyronConversationTranscriptRow] = []
        rows.reserveCapacity(messages.count)
        var index = messages.startIndex
        while index < messages.endIndex {
            let message = messages[index]
            let next = messages.index(after: index)
            if next < messages.endIndex,
                let reply = Self.pairedReply(after: message, reply: messages[next], ownership: ownership) {
                rows.append(reply)
                index = messages.index(after: next)
            } else {
                let answers = message.conversationRole == .user ? message.clarificationAnswers ?? [] : []
                rows.append(VyronConversationTranscriptRow(message: message, clarificationAnswers: answers))
                index = next
            }
        }
        self.rows = rows
    }

    private static func pairedReply(
        after prompt: ChatMessage,
        reply: ChatMessage,
        ownership: VyronConversationResponseOwnership
    ) -> VyronConversationTranscriptRow? {
        guard prompt.conversationRole == .assistant, reply.conversationRole == .user,
            let responseID = prompt.parentResponseID, responseID == reply.parentResponseID,
            ownership.isChild(prompt), ownership.isChild(reply)
        else { return nil }

        if let answers = reply.clarificationAnswers, let first = answers.first {
            guard prompt.content == first.question || prompt.content.hasPrefix(first.question + "\n") else {
                return nil
            }
            return VyronConversationTranscriptRow(message: reply, clarificationAnswers: answers)
        }
        guard let answer = legacyAnswer(prompt: prompt.content, reply: reply.content) else { return nil }
        return VyronConversationTranscriptRow(message: reply, clarificationAnswers: [answer])
    }

    private static func legacyAnswer(prompt: String, reply: String) -> VyronClarificationAnswer? {
        // The old separator also occurred in free text, so only recover an unambiguous single prompt.
        guard !prompt.contains("\n\n"), !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        var questions = [prompt]
        let lines = prompt.components(separatedBy: "\n")
        if let optionIndex = lines.indices.dropFirst().first(where: { lines[$0].hasPrefix("- ") }) {
            let optionLines = lines[optionIndex...]
            if legacyOptionCount.contains(optionLines.count), optionLines.allSatisfy({ $0.hasPrefix("- ") }) {
                questions.append(lines[..<optionIndex].joined(separator: "\n"))
            }
        }
        let matches = questions.compactMap { question -> VyronClarificationAnswer? in
            let prefix = question + "\n"
            guard reply.hasPrefix(prefix) else { return nil }
            let answer = String(reply.dropFirst(prefix.count))
            guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return VyronClarificationAnswer(question: question, answer: answer)
        }
        return matches.count == 1 ? matches.first : nil
    }
}
