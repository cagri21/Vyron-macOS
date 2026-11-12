import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronDeepSeekReplayScope: Sendable {
    static let maximumResponseBytes = 2_097_152
    let source: String
    let model: String

    init?(connection: ModelConnectionProfile, model: String) {
        guard VyronDeepSeekRoute.matches(connection),
            let endpoint = try? ModelEndpoint.validated(connection.endpoint, kind: connection.kind)
        else { return nil }
        source = "deepseek.chat.v1:\(connection.id.uuidString):\(endpoint.absoluteString)"
        self.model = model
    }

    func scoped(_ messages: [DevelopmentMessage]) -> [DevelopmentMessage] {
        messages.map { message in
            guard message.role == "assistant", let continuation = message.continuation,
                continuation.source == source, continuation.model == model
            else {
                return message.discardingContinuation()
            }
            return message
        }
    }

    func reasoning(for message: DevelopmentMessage) throws -> String? {
        guard message.role == "assistant" else { return nil }
        guard let continuation = message.continuation,
            continuation.source == source, continuation.model == model
        else { return "" }
        guard continuation.state.count <= Self.maximumResponseBytes else { throw invalidState }
        let state: VyronDeepSeekReplayState
        do {
            state = try JSONDecoder().decode(VyronDeepSeekReplayState.self, from: continuation.state)
        } catch {
            throw invalidState
        }
        guard state.content == message.content, (state.calls ?? []) == (message.toolCalls ?? []),
            message.toolName == nil, message.toolCallID == nil
        else { throw invalidState }
        return state.reasoning
    }

    func retaining(_ message: DevelopmentMessage, reasoning: String?) throws -> DevelopmentMessage {
        guard let reasoning else { return message }
        let state = try JSONEncoder().encode(
            VyronDeepSeekReplayState(
                content: message.content,
                calls: message.toolCalls,
                reasoning: reasoning
            )
        )
        guard state.count <= Self.maximumResponseBytes else { throw invalidState }
        return DevelopmentMessage(
            message: message,
            continuation: VyronModelContinuation(
                source: source,
                model: model,
                state: state
            )
        )
    }

    private var invalidState: ModelProviderError {
        .invalidResponse(VyronModelDataText.deepSeekInvalidToolExchange)
    }
}
