import Foundation
import VyronLocalization
import VyronModelDomain

extension OllamaClient {
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
        var messages = input.messages
        let systemPrompt = input.configuration.systemPrompt
        try validateName(model)
        try VyronImageAttachment.validate(messages: messages)
        // A local endpoint may offer a cloud-backed model under an ordinary name.
        let installed = try await catalog(path: "tags")
        guard let selected = installed.first(where: { Self.sameModelName($0.name, model) }) else {
            throw LocalAIError.modelNotInstalled(model)
        }
        guard configuredConnection || !selected.isRemote else { throw LocalAIError.cloudModelNotAllowed }
        if messages.contains(where: { $0.images?.isEmpty == false }) {
            let capabilities: [String]?
            if let advertised = selected.capabilities, !advertised.isEmpty {
                capabilities = advertised
            } else {
                capabilities = try await modelMetadata(for: selected.name).capabilities
            }
            if capabilities?.contains("vision") != true {
                messages = try await imageTextPreparation.chatMessages(messages)
            }
        }
        try Task.checkCancellation()
        let imageCount = messages.reduce(0) { $0 + ($1.images?.count ?? 0) }
        var wireMessages = messages.map { message in
            var wire = VyronOllamaChatMessage(role: message.role, content: message.content)
            if let images = message.images, !images.isEmpty {
                wire.images = images.map { $0.data.base64EncodedString() }
            }
            return wire
        }
        guard wireMessages.allSatisfy({ ["user", "assistant", "system"].contains($0.role) }) else {
            throw LocalAIError.invalidResponse(VyronModelDataText.unsupportedMessageRole)
        }
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            wireMessages.insert(VyronOllamaChatMessage(role: "system", content: systemPrompt), at: 0)
        }
        let descriptor = ModelCatalog.descriptor(for: selected.name)
        let modelContext = descriptor?.role == .coding ? descriptor?.recommendedContextTokens ?? 32_768 : 32_768
        let context = try await requestedContext(for: selected.localModel, fallback: min(modelContext, 32_768))
        let textMessages = wireMessages.map { VyronOllamaChatMessage(role: $0.role, content: $0.content) }
        let inputBudget =
            try JSONEncoder().encode(textMessages).count + 2_048
            + imageCount * VyronImageAttachment.estimatedContextTokens
        let desiredOutput = settings.maxOutputTokens ?? input.configuration.effort.developmentBudget.outputTokens
        let outputBudget = min(desiredOutput, context - inputBudget)
        guard outputBudget >= min(settings.maxOutputTokens ?? 512, 512) else {
            throw LocalAIError.invalidResponse(
                VyronModelDataText.ollamaChatContextExceeded
            )
        }
        let thinking = try await structuredThinkingOption(
            for: selected.localModel,
            effort: input.configuration.effort
        )
        let body = VyronOllamaChatRequest(
            model: model,
            messages: wireMessages,
            think: thinking,
            options: VyronOllamaChatOptions(
                num_ctx: context,
                num_predict: outputBudget,
                temperature: settings.temperature ?? 0.3,
                top_p: settings.topP
            )
        )
        let request = try makeRequest(path: "chat", body: body)
        let (bytes, response) = try await stream(request)
        defer { bytes.task.cancel() }
        try await validate(response: response, bytes: bytes)
        var output = ""
        var finished = false
        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let event: ChatEvent = try Self.decodeLine(line)
                if let error = event.error { throw serverError(error) }
                if let token = event.message?.content, !token.isEmpty {
                    output += token
                    onToken(token)
                }
                if event.done == true {
                    finished = true
                    break
                }
            }
            try Task.checkCancellation()
        } catch {
            throw Self.normalized(error)
        }
        guard finished else { throw LocalAIError.incompleteStream }
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalAIError.invalidResponse(
                VyronModelDataText.ollamaChatNoAnswer
            )
        }
        return output
    }
}
