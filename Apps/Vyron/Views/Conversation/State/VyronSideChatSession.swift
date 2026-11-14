import Combine
import Foundation
import VyronCore

@MainActor
final class VyronSideChatSession: ObservableObject {
    @Published var draft = ""
    @Published private(set) var isGenerating = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var unsavedAnswer: String?

    let context: VyronSideChatContext
    let configuration: VyronSideChatConfiguration
    private weak var owner: AppModel?
    private(set) var activeResponse: VyronSideChatResponse?
    private var generationTask: Task<Void, Never>?
    private var tokenConsumer: Task<Void, Never>?
    private var tokenContinuation: AsyncStream<String>.Continuation?
    private var pendingPrompt: String?

    init(context: VyronSideChatContext, configuration: VyronSideChatConfiguration, owner: AppModel) {
        self.context = context
        self.configuration = configuration
        self.owner = owner
    }

    var canSend: Bool {
        !isGenerating && owner?.canSendSideChat(context.conversationID) == true
            && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func owns(_ response: VyronSideChatResponse) -> Bool {
        activeResponse == response && isGenerating
    }

    func send() {
        guard canSend, let owner else { return }
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.utf8.count <= VyronConversationLimits.maximumMessageBytes else {
            errorMessage = VyronStatusText.messageTooLong
            return
        }
        guard let turn = owner.beginSideChatTurn(context, prompt: prompt) else {
            errorMessage = VyronHeaderText.sideChatSaveFailed
            return
        }
        errorMessage = nil
        pendingPrompt = prompt
        draft = ""
        activeResponse = turn.response
        isGenerating = true
        let configuration = configuration
        let (tokens, continuation) = AsyncStream<String>.makeStream()
        tokenContinuation = continuation
        let consumer = Task { @MainActor [weak self] in
            for await token in tokens {
                guard let self, self.owns(turn.response), !Task.isCancelled else { continue }
                self.owner?.appendSideChatToken(token, response: turn.response)
            }
        }
        tokenConsumer = consumer
        generationTask = Task { @MainActor [weak self] in
            guard !Task.isCancelled, self?.owns(turn.response) == true, self?.owner?.isShuttingDown == false else {
                continuation.finish()
                consumer.cancel()
                return
            }
            do {
                let answer = try await VyronChatInference.response(
                    using: configuration.provider,
                    request: VyronChatInferenceRequest(
                        model: configuration.model, messages: turn.messages,
                        configuration: VyronChatInferenceConfiguration(
                            systemPrompt: VyronConversationRequestContext.systemPrompt, effort: configuration.effort
                        )
                    ),
                    onToken: { token in continuation.yield(token) }
                )
                continuation.finish()
                await consumer.value
                guard let self, self.owns(turn.response), !Task.isCancelled else { return }
                if answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.finish(
                        turn.response, content: nil, state: .failed, detail: VyronHeaderText.sideChatNoAnswer
                    )
                } else {
                    self.finish(turn.response, content: answer, state: .completed, detail: nil)
                }
            } catch {
                continuation.finish()
                consumer.cancel()
                await consumer.value
                guard let self, self.owns(turn.response) else { return }
                let cancelled = Task.isCancelled || error is CancellationError
                self.finish(
                    turn.response,
                    content: nil,
                    state: cancelled ? .stopped : .failed,
                    detail: cancelled ? nil : error.localizedDescription
                )
            }
        }
    }

    @discardableResult
    func stop() -> Task<Void, Never>? {
        let task = generationTask
        task?.cancel()
        tokenContinuation?.finish()
        tokenConsumer?.cancel()
        if let response = activeResponse {
            finish(response, content: nil, state: .stopped, detail: nil)
        }
        return task
    }

    private func finish(
        _ response: VyronSideChatResponse,
        content: String?,
        state: ResponseActivity.State,
        detail: String?
    ) {
        guard owns(response) else { return }
        owner?.connectionBalances.responseCompleted(configuration.connection.id)
        let conversation = owner?.sideChatConversation(with: response.conversationID)
        let answer = content ?? conversation?.messages.first(where: { $0.id == response.messageID })?.content
        let saved = owner?.finishSideChatResponse(response, content: content, state: state, detail: detail) == true
        if saved {
            unsavedAnswer = nil
        } else {
            if draft.isEmpty, let pendingPrompt { draft = pendingPrompt }
            unsavedAnswer = answer?.isEmpty == false ? answer : nil
        }
        pendingPrompt = nil
        activeResponse = nil
        isGenerating = false
        generationTask = nil
        tokenContinuation = nil
        tokenConsumer = nil
        errorMessage = saved ? detail : VyronHeaderText.sideChatSaveFailed
    }
}
