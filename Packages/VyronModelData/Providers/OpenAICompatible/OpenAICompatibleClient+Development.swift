import Foundation
import VyronLocalization
import VyronModelDomain

extension OpenAICompatibleClient {
    public func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        if !model.isEmpty { try requireNativeTools(for: model) }
        let selectedID: String
        let discovered: [LocalModel]
        do { discovered = try await models() } catch ModelProviderError.modelListUnavailable { discovered = [] }
        if !model.isEmpty {
            selectedID = model
        } else if automaticModelSelection, let candidate = discovered.first {
            selectedID = candidate.name
        } else {
            throw ModelProviderError.invalidModel
        }
        try ModelEndpoint.validateModelID(selectedID)
        try requireNativeTools(for: selectedID)
        let selected = discovered.first { $0.name == selectedID } ?? LocalModel(name: selectedID, size: 0)
        if !verifiedToolModels.contains(selectedID) {
            if selected.capabilities?.contains("tools") == true {
                verifiedToolModels.insert(selectedID)
            } else {
                try await verifyToolSupport(model: selectedID)
            }
        }
        return LocalModel(
            name: selected.name,
            size: selected.size,
            parameterSize: selected.parameterSize,
            quantization: selected.quantization,
            capabilities: Array(Set((selected.capabilities ?? []) + ["tools"])).sorted()
        )
    }

    public func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort = .balanced,
        mode: DevelopmentMode = .agent
    ) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode, externalTools: [])
    }

    public func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        try ModelEndpoint.validateModelID(model)
        let limits = VyronDeepSeekModelBudget.published(for: connection, model: model)
        let requested = try requestedBudget(limits: limits, effort: effort)
        let scope = VyronDeepSeekReplayScope(connection: connection, model: model)
        let messages = scope?.scoped(messages) ?? messages.map { $0.discardingContinuation() }
        try VyronDevelopmentImageContext.validate(messages)
        let containsImages = VyronDevelopmentImageContext.imageCount(in: messages) > 0
        if !verifiedToolModels.contains(model) {
            _ = try await developmentModel(model: model, automaticModelSelection: false, effort: effort)
        }
        if containsImages { try validateImageSupport(model: model) }
        guard !messages.isEmpty, messages.allSatisfy({ ["system", "user", "assistant", "tool"].contains($0.role) })
        else { throw DevelopmentAgentError.contextBudget }
        let tools = try DevelopmentToolDefinition.available(mode: mode, externalTools: externalTools)
        let bounded = try VyronDevelopmentRequestBudget.messages(
            messages,
            tools: tools,
            budget: limits == nil ? .init(contextTokens: requested.contextTokens) : requested,
            encodedMessageBytes: {
                try JSONEncoder().encode($0.map { try VyronCompatibleMessage($0, scope: scope) }).count
            }
        )
        let wire = try bounded.map { try VyronCompatibleMessage($0, scope: scope) }
        let maximum: Int
        if limits != nil {
            maximum = requested.outputTokens
        } else {
            maximum = try outputBudget(messages: wire, tools: tools, budget: requested, minimum: 512)
        }
        let body = VyronCompatibleChatRequest(
            model: model,
            messages: wire,
            stream: false,
            maxTokens: maximum,
            temperature: settings.temperature,
            topP: settings.topP,
            tools: tools
        )
        let reply = try await completion(configured(body, effort: effort))
        var result = try reply.developmentMessage()
        if let scope {
            result = try scope.retaining(result, reasoning: reply.choices.first?.message.reasoningContent)
        }
        guard !hasUnfencedDevelopmentToolMarkup(result.content) || !(result.toolCalls ?? []).isEmpty else {
            throw DevelopmentAgentError.invalidTool(
                VyronModelDataText.serverPrintedToolMarkup
            )
        }
        let allowed = Set(tools.map { $0.function.name })
        guard (result.toolCalls ?? []).allSatisfy({ allowed.contains($0.function.name) }) else {
            throw DevelopmentAgentError.invalidTool(VyronModelDataText.toolUnavailableInMode)
        }
        return DevelopmentStep(message: result)
    }

    private func verifyToolSupport(model: String) async throws {
        let nonce = UUID().uuidString
        let probe = DevelopmentToolDefinition(
            function: .init(
                name: "vyron_check_tools",
                description:
                    "Verify native tool transport. This is a data-only capability check; no action will execute.",
                parameters: .init(
                    properties: ["nonce": .init(type: "string", description: "Copy the supplied nonce exactly.")],
                    required: ["nonce"]
                )
            )
        )
        let messages = [
            VyronCompatibleMessage(
                role: "user",
                content: "Call vyron_check_tools with nonce \(nonce). This is a capability check only."
            )
        ]
        let body = VyronCompatibleChatRequest(
            model: model,
            messages: messages,
            stream: false,
            maxTokens: min(settings.maxOutputTokens ?? 2_048, 2_048),
            tools: [probe],
            toolChoice: .init(function: .init(name: "vyron_check_tools"))
        )
        // The probe checks function transport, with thinking disabled to bound its cost and permit forced selection.
        let reply = try await completion(configured(body, effort: .quick, isProbe: true))
        let message = try reply.developmentMessage()
        guard let calls = message.toolCalls, calls.count == 1, calls[0].function.name == "vyron_check_tools",
            calls[0].function.arguments == ["nonce": .string(nonce)]
        else { throw ModelProviderError.unsupportedTools }
        verifiedToolModels.insert(model)
    }

    private func requireNativeTools(for model: String) throws {
        let report = VyronModelFeaturePolicy.assess(
            VyronModelFeatureContext(
                connection: connection,
                model: LocalModel(name: model, size: 0)
            )
        )
        guard report[.agent].isEnabled else { throw ModelProviderError.unsupportedTools }
    }

}
