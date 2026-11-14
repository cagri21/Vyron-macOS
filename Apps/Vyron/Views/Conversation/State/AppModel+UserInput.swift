import Foundation
import VyronCore

extension AppModel {
    var selectedUserInputRequest: VyronUserInputRequest? {
        guard let generation = interactions.userInputGeneration,
            let owner = foregroundRun.response(forGeneration: generation),
            owner.conversationID == selectedConversationID,
            owner.conversationID == interactions.userInputConversationID,
            ownsInteractiveWorkResponse(owner) else { return nil }
        return interactions.pendingUserInput
    }

    func requestDevelopmentUserInput(
        _ request: VyronUserInputRequest,
        generationID: UUID
    ) async throws -> VyronUserInputResponse {
        try Task.checkCancellation()
        guard let owner = foregroundRun.response(forGeneration: generationID), ownsInteractiveWorkResponse(owner)
        else { throw CancellationError() }
        return try await interactions.requestUserInput(
            request,
            generationID: generationID,
            conversation: { ownsInteractiveWorkResponse(owner) ? owner.conversationID : nil },
            didPresent: {
                if selectedConversationID == owner.conversationID { statusMessage = VyronQuestionText.waitingForAnswer }
            }
        )
    }

    func respondToUserInput(_ response: VyronUserInputResponse) {
        guard selectedUserInputRequest?.id == response.requestID,
            let generation = interactions.userInputGeneration,
            let owner = foregroundRun.response(forGeneration: generation) else { return }
        if interactions.respondToUserInput(
            response,
            conversationID: owner.conversationID,
            canRespond: { $0 == generation && ownsInteractiveWorkResponse(owner) },
            record: { recordUserInputResponse(response, request: $0, owner: owner) }
        ) {
            statusMessage = nil
        }
    }

    func cancelPendingUserInput(generationID: UUID? = nil) {
        if let generationID, interactions.userInputGeneration != generationID { return }
        interactions.cancelPendingUserInput()
    }

    private func recordUserInputResponse(
        _ response: VyronUserInputResponse, request: VyronUserInputRequest, owner: VyronResponseIdentity
    ) {
        guard let conversationIndex = conversations.firstIndex(where: { $0.id == owner.conversationID }),
            let messageIndex = conversations[conversationIndex].messages.firstIndex(where: {
                $0.id == owner.messageID
            })
        else { return }
        let questions = request.questions.map { question in
            let options = question.options.map { option in
                "- " + option.label + (option.description.isEmpty ? "" : ": " + option.description)
            }
            return ([question.question] + options).joined(separator: "\n")
        }.joined(separator: "\n\n")
        let answers = request.questions.map { question in
            let value = response.answers.first { $0.questionID == question.id }?.value ?? ""
            return VyronClarificationAnswer(question: question.question, answer: value)
        }
        var questionMessage = ChatMessage(role: .assistant, content: questions)
        questionMessage.parentResponseID = owner.messageID
        var answerMessage = ChatMessage(
            role: .user, content: answers.map { $0.question + "\n" + $0.answer }.joined(separator: "\n\n")
        )
        answerMessage.parentResponseID = owner.messageID
        answerMessage.clarificationAnswers = answers
        conversations[conversationIndex].messages.insert(
            contentsOf: [questionMessage, answerMessage], at: messageIndex
        )
        conversations[conversationIndex].updatedAt = Date()
        saveHistory()
    }
}
