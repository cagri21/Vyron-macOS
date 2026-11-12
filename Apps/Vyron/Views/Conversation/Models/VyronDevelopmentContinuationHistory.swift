import Foundation
import VyronCore

/// Links an explicit continuation to real user turns in this conversation, never assistant claims about a goal.
enum VyronDevelopmentContinuationHistory {
    static func context(
        for currentGoal: String,
        messages: [ChatMessage]
    ) -> VyronDevelopmentContinuationContext? {
        let messages = VyronConversationCompactionCommand.taskHistory(messages)
        guard VyronDevelopmentContinuationContext.isContinuationRequest(currentGoal),
            messages.last?.conversationRole == .user
        else { return nil }
        var currentGroupStart = messages.count - 1
        while currentGroupStart > 0, messages[currentGroupStart - 1].conversationRole == .user {
            currentGroupStart -= 1
        }
        guard VyronDevelopmentContinuationContext.isContinuationRequest(messages[currentGroupStart].content) else {
            return nil
        }

        var originalGoal: String?
        var responseIDs: [UUID] = []
        var guidance: [String] = []
        var isUserGroup = false
        let ownership = VyronConversationResponseOwnership(messages: messages)
        for message in messages.prefix(currentGroupStart) {
            if ownership.isChild(message) {
                let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.conversationRole == .user, originalGoal != nil, !text.isEmpty,
                    !VyronDevelopmentContinuationContext.isContinuationRequest(text) {
                    guidance.append(text)
                }
                continue
            }
            if message.conversationRole == .user {
                let text = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                let isContinuation = VyronDevelopmentContinuationContext.isContinuationRequest(text)
                if !isUserGroup, !isContinuation {
                    originalGoal = text.isEmpty ? nil : text
                    responseIDs.removeAll(keepingCapacity: true)
                    guidance.removeAll(keepingCapacity: true)
                } else if isUserGroup, !text.isEmpty, !isContinuation {
                    guidance.append(text)
                }
                isUserGroup = true
            } else {
                isUserGroup = false
                if message.conversationRole == .assistant, originalGoal != nil {
                    responseIDs.append(message.id)
                }
            }
        }
        guard let originalGoal, !responseIDs.isEmpty else { return nil }
        return VyronDevelopmentContinuationContext(
            originalGoal: originalGoal, priorResponseIDs: responseIDs, guidance: guidance
        )
    }
}
