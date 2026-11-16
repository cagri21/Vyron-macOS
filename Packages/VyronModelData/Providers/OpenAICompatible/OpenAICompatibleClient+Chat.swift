import Foundation
import VyronLocalization
import VyronModelDomain

extension OpenAICompatibleClient {
    public func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String? = nil,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        try await chat(
            VyronChatInferenceRequest(
                model: model,
                messages: messages,
                configuration: VyronChatInferenceConfiguration(systemPrompt: systemPrompt, effort: .automatic)
            ),
            onToken: onToken
        )
    }

    package func chat(
        _ input: VyronChatInferenceRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let model = input.model
        let messages = input.messages
        let systemPrompt = input.configuration.systemPrompt
        try ModelEndpoint.validateModelID(model)
        try VyronImageAttachment.validate(messages: messages)
        guard messages.allSatisfy({ ["user", "assistant", "system"].contains($0.role) }) else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.unsupportedMessageRole)
        }
        let containsImages = messages.contains { $0.images?.isEmpty == false }
        if containsImages { try validateImageSupport(model: model) }
        var wire = messages.map { message in
            var wire = VyronCompatibleMessage(role: message.role, content: message.content)
            wire.images = message.images
            return wire
        }
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wire.insert(.init(role: "system", content: systemPrompt), at: 0)
        }
        let limits = VyronDeepSeekModelBudget.published(for: connection, model: model)
        let maximum = try outputBudget(
            messages: wire,
            tools: [],
            budget: requestedBudget(limits: limits, model: model, effort: input.configuration.effort),
            minimum: 1
        )
        let body = VyronCompatibleChatRequest(
            model: model,
            messages: wire,
            stream: true,
            maxTokens: maximum,
            temperature: settings.temperature,
            topP: settings.topP
        )
        let usageRequest = VyronOpenAIUsageRequest(model: model)
        var usageResponse: DevelopmentJSONValue?
        var reported = false
        var attempted = false
        do {
            let configuredBody = configured(body, effort: input.configuration.effort)
            var request = try request(path: "chat/completions", body: configuredBody)
            attempted = true
            let initial = try await session.bytes(for: request)
            var bytes = initial.0
            var response = initial.1
            defer { bytes.task.cancel() }
            try Task.checkCancellation()
            if let http = response as? HTTPURLResponse, [400, 422].contains(http.statusCode),
                !usesCompletionTokenLimit {
                var detail = Data()
                for try await byte in bytes {
                    try Task.checkCancellation()
                    guard detail.count < 16_384 else { break }
                    detail.append(byte)
                }
                if requestsCompletionTokenLimit(detail) {
                    bytes.task.cancel()
                    usesCompletionTokenLimit = true
                    request = try self.request(path: "chat/completions", body: configuredBody)
                    let retry = try await session.bytes(for: request)
                    bytes = retry.0; response = retry.1
                }
            }
            guard let http = response as? HTTPURLResponse else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.missingHTTPResponse)
            }
            guard (200..<300).contains(http.statusCode) else { throw ModelProviderError.http(http.statusCode) }
            var payload: [String] = []
            var payloadBytes = 0
            var output = ""
            var reasoningBytes = 0
            var finished = false
            var stopped = false
            var deferredFailure: ModelProviderError?
            func consume() throws {
                guard !payload.isEmpty else { return }
                let event = payload.joined(separator: "\n")
                payload.removeAll(keepingCapacity: true)
                payloadBytes = 0
                if event == "[DONE]" { finished = true; return }
                if usageHandler != nil {
                    usageResponse = VyronOpenAIUsageDecoding.response(Data(event.utf8)) ?? usageResponse
                }
                let chunk = try JSONDecoder().decode(VyronCompatibleStreamEvent.self, from: Data(event.utf8))
                guard chunk.error == nil else {
                    throw ModelProviderError.invalidResponse(VyronModelDataText.serverStreamError)
                }
                for choice in chunk.choices ?? [] where choice.index == nil || choice.index == 0 {
                    // Private provider reasoning is consumed only as bounded transport data, never visible tokens.
                    reasoningBytes += choice.delta?.reasoningContent?.utf8.count ?? 0
                    guard reasoningBytes <= VyronDeepSeekReplayScope.maximumResponseBytes else {
                        throw ModelProviderError.invalidResponse(VyronModelDataText.reasoningResponseTooLarge)
                    }
                    if let token = choice.delta?.content, !token.isEmpty {
                        guard output.utf8.count + token.utf8.count <= 2_097_152 else {
                            throw ModelProviderError.invalidResponse(VyronModelDataText.answerTooLarge)
                        }
                        output += token
                        onToken(token)
                    }
                    if let reason = choice.finishReason {
                        guard reason == "stop" else {
                            let failure = ModelProviderError.invalidResponse(
                                reason == "length"
                                    ? "The answer reached the output limit. Increase the limit or shorten the request."
                                    : "The server did not finish with a text answer."
                            )
                            // OpenAI sends the final usage chunk after finish_reason, including truncated answers.
                            if usageHandler != nil { deferredFailure = failure; continue }
                            throw failure
                        }
                        stopped = true
                    }
                }
            }
            func consumeLine(_ data: Data) throws {
                guard let raw = String(data: data, encoding: .utf8) else {
                    throw ModelProviderError.invalidResponse(VyronModelDataText.invalidStreamingText)
                }
                let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
                if line.isEmpty { try consume(); return }
                if line.hasPrefix("data:") {
                    let value = String(line.dropFirst(5)).trimmingCharacters(in: .init(charactersIn: " "))
                    payloadBytes += value.utf8.count
                    guard payloadBytes <= 2_097_152 else {
                        throw ModelProviderError.invalidResponse(VyronModelDataText.streamingEventTooLarge)
                    }
                    payload.append(value)
                }
            }
            var line = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                if byte == 10 {
                    try consumeLine(line)
                    line.removeAll(keepingCapacity: true)
                    if finished { break }
                } else {
                    guard line.count < 2_097_152 else {
                        throw ModelProviderError.invalidResponse(VyronModelDataText.streamingEventTooLarge)
                    }
                    line.append(byte)
                }
            }
            if !line.isEmpty { try consumeLine(line) }
            try consume()
            await reportUsage(usageRequest, response: usageResponse)
            reported = true
            try Task.checkCancellation()
            if let deferredFailure { throw deferredFailure }
            guard finished || stopped else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.responseEndedEarly)
            }
            guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.serverNoAnswer)
            }
            return output
        } catch {
            if attempted, !reported, !isRejectedUsageRequest(error) {
                await reportUsage(usageRequest, response: usageResponse)
            }
            throw normalizedProviderError(error)
        }
    }

}
