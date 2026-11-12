import Foundation
import VyronCore

@MainActor
final class VyronConversationFollowUpRequests {
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    func start(
        using provider: any ModelProvider,
        request: VyronConversationFollowUpRequest,
        deliver: @escaping @MainActor (VyronResponseIdentity, [String]) -> Void
    ) {
        cancel()
        guard !Task.isCancelled else { return }
        let id = UUID()
        requestID = id
        task = Task { [weak self] in
            let questions: [String]
            do {
                questions = try await FollowUpQuestions.generate(
                    provider: provider,
                    model: request.model,
                    prompt: request.prompt,
                    answer: request.answer
                )
            } catch {
                // Optional suggestions must never surface an error over a completed answer.
                questions = []
            }
            guard let self, self.requestID == id, !Task.isCancelled else { return }
            self.requestID = nil
            self.task = nil
            guard !questions.isEmpty else { return }
            deliver(request.response, questions)
        }
    }

    @discardableResult
    func cancel() -> Task<Void, Never>? {
        let cancelledTask = task
        requestID = nil
        task = nil
        cancelledTask?.cancel()
        return cancelledTask
    }
}
