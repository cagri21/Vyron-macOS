import Foundation
import VyronCore

/// Projects a repeated request for inference without changing its saved transcript or earlier dependencies.
struct VyronDevelopmentRetryContext: Sendable {
    let messages: [ChatMessage]
    let referenceMessages: [ChatMessage]
    let compaction: VyronConversationCompaction?
    let isFreshRetry: Bool

    init(prompt: String, history: [ChatMessage], compaction: VyronConversationCompaction?) {
        let goal = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownership = VyronConversationResponseOwnership(messages: history)
        let taskMessages = VyronConversationCompactionCommand.taskHistory(history)
        let roots = taskMessages.indices.filter {
            taskMessages[$0].conversationRole == .user && !ownership.isChild(taskMessages[$0])
        }
        guard !goal.isEmpty, !Self.isDependentReply(goal), roots.count > 1,
            let current = roots.last, taskMessages[current].id == history.last?.id,
            Self.goal(in: taskMessages[current]) == goal,
            Self.goal(in: taskMessages[roots[roots.count - 2]]) == goal
        else {
            messages = history
            referenceMessages = history
            self.compaction = compaction
            isFreshRetry = false
            return
        }

        var firstRepeated = current
        for index in roots.dropLast().reversed() {
            guard Self.goal(in: taskMessages[index]) == goal else { break }
            firstRepeated = index
        }
        let firstID = taskMessages[firstRepeated].id
        let hasPriorAnswer = taskMessages.suffix(from: firstRepeated).contains {
            $0.conversationRole == .assistant && !ownership.isChild($0)
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard hasPriorAnswer, let start = history.firstIndex(where: { $0.id == firstID }) else {
            messages = history
            referenceMessages = history
            self.compaction = compaction
            isFreshRetry = false
            return
        }
        messages = history.enumerated().compactMap { index, message in
            if index >= start, message.conversationRole == .assistant, !ownership.isChild(message) { return nil }
            return message
        }
        let redundantGoals = Set(taskMessages.indices.filter { index in
            let message = taskMessages[index]
            return index >= firstRepeated && index != current && message.conversationRole == .user
                && !ownership.isChild(message) && Self.goal(in: message) == goal && !Self.hasAttachments(message)
        }.map { taskMessages[$0].id })
        referenceMessages = messages.filter { !redundantGoals.contains($0.id) }
        // A lossy summary cannot separate old assistant claims from real user guidance. Raw user turns remain above.
        self.compaction = nil
        isFreshRetry = true
    }

    private static func goal(in message: ChatMessage) -> String {
        message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func hasAttachments(_ message: ChatMessage) -> Bool {
        message.images?.isEmpty == false || message.pdfPreviews?.isEmpty == false
            || message.fileAttachments?.isEmpty == false || message.applicationAttachments?.isEmpty == false
            || message.capturedImages?.isEmpty == false || message.developmentTaskFilename != nil
            || message.clarificationAnswers != nil
    }

    private static func isDependentReply(_ text: String) -> Bool {
        if VyronDevelopmentContinuationContext.isContinuationRequest(text) { return true }
        let normalized = text.trimmingCharacters(in: .punctuationCharacters)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        return dependentReplies.contains(normalized)
    }

    private static let dependentReplies: Set<String> = [
        "yes", "no", "ok", "okay", "sure", "go ahead", "do it", "proceed", "please do", "please do it",
        "please go ahead", "yes please", "no thanks", "thanks", "thank you", "got it", "sounds good",
        "evet", "hayır", "hayir", "tamam", "olur", "peki", "teşekkürler", "tesekkurler",
        "так", "ні", "добре", "гаразд", "вперед", "роби", "зроби це", "дякую"
    ]
}
