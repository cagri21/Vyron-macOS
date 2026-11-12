import Foundation
import VyronLocalization
import VyronModelDomain

/// Native Claude Messages, model discovery, and client tool transport.
public actor VyronAnthropicClient: ModelProvider, VyronEffortChatProviding, VyronDevelopmentMessageBudgetProviding {
    // Anthropic's counter includes system tokens but may differ slightly from generation.
    private static let tokenCountHeadroom = 128
    private let transport: VyronAnthropicTransport
    private let settings: ModelSettings
    private var verifiedToolModels: Set<String> = []

    public init(connection: ModelConnectionProfile, apiKey: String? = nil) throws {
        try self.init(connection: connection, apiKey: apiKey, configuration: .ephemeral)
    }

    init(
        connection: ModelConnectionProfile,
        apiKey: String? = nil,
        configuration: URLSessionConfiguration
    ) throws {
        let profile = try connection.validated()
        guard profile.kind == .anthropic else { throw ModelProviderError.invalidEndpoint }
        let endpoint = try ModelEndpoint.validated(profile.endpoint, kind: .anthropic)
        transport = VyronAnthropicTransport(
            endpoint: endpoint,
            apiKey: try validatedModelAPIKey(apiKey),
            session: modelProviderSession(configuration: configuration)
        )
        settings = profile.settings
    }

    deinit { transport.session.invalidateAndCancel() }

    public func models() async throws -> [LocalModel] {
        do { return try await transport.models() } catch { throw normalizedProviderError(error) }
    }

    package nonisolated func developmentMessageBudget(for model: String) -> VyronDevelopmentMessageBudget {
        VyronClaudeModelBudget.developmentMessages
    }

    public func chat(
        model: String,
        messages: [ChatMessage],
        systemPrompt: String?,
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
        _ request: VyronChatInferenceRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        do {
            try ModelEndpoint.validateModelID(request.model)
            let model = request.model
            let limits = try VyronClaudeModelBudget.validated(settings, for: model)
            let context = limits.contextTokens ?? VyronClaudeModelBudget.contextTokens(for: model)
            let output = outputAllowance(for: request.configuration.effort, context: context)
            let input = try VyronAnthropicWire.chatInput(
                request.messages,
                systemPrompt: request.configuration.systemPrompt
            )
            let textMessages = request.messages.map { message in
                var text = message
                text.images = nil
                return text
            }
            let textInput = try VyronAnthropicWire.chatInput(
                textMessages,
                systemPrompt: request.configuration.systemPrompt,
                retainingEmptyUserTurns: true
            )
            let imageTokens =
                request.messages.reduce(0) { $0 + ($1.images?.count ?? 0) }
                * VyronImageAttachment.estimatedContextTokens
            let estimate = try Self.estimatedMessageBytes(textInput) + imageTokens
            if estimate + output + VyronDevelopmentRequestBudget.requestOverheadTokens > context {
                try await verifyContext(
                    model: model,
                    input: input,
                    tools: [],
                    budget: .init(
                        contextTokens: context,
                        outputTokens: output
                    )
                )
            }
            let body = try VyronAnthropicWire.request(
                model: model,
                input: input,
                options: .init(maximumOutputTokens: output, stream: true)
            )
            let stream = try await transport.stream(body, model: model, onToken: onToken)
            return stream.output
        } catch { throw normalizedProviderError(error) }
    }

    public func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        do {
            let selected: String
            if model.isEmpty, automaticModelSelection {
                selected = try await models().first?.name ?? ""
            } else {
                selected = model
            }
            try ModelEndpoint.validateModelID(selected)
            try await verifyTools(model: selected)
            return LocalModel(name: selected, size: 0, capabilities: ["tools"])
        } catch { throw normalizedProviderError(error) }
    }

    public func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode
    ) async throws -> DevelopmentStep {
        try await developmentStep(model: model, messages: messages, effort: effort, mode: mode, externalTools: [])
    }

    // The stable ModelProvider signature carries native integration tools.
    public func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        do {
            try ModelEndpoint.validateModelID(model)
            let limits = try VyronClaudeModelBudget.validated(settings, for: model)
            guard !messages.isEmpty else { throw DevelopmentAgentError.contextBudget }
            let definitions = try DevelopmentToolDefinition.available(mode: mode, externalTools: externalTools)
            let context = limits.contextTokens ?? VyronClaudeModelBudget.contextTokens(for: model)
            let output = outputAllowance(for: effort, context: context)
            let result = try await developmentCompletion(
                model: model,
                messages: messages,
                definitions: definitions,
                budget: .init(contextTokens: context, outputTokens: output)
            )
            let allowed = Set(definitions.map { $0.function.name })
            guard (result.toolCalls ?? []).allSatisfy({ allowed.contains($0.function.name) }) else {
                throw DevelopmentAgentError.invalidTool(VyronModelDataText.toolUnavailableInMode)
            }
            guard !hasUnfencedDevelopmentToolMarkup(result.content) || result.toolCalls?.isEmpty == false else {
                throw DevelopmentAgentError.invalidTool(
                    VyronModelDataText.serverPrintedToolMarkup
                )
            }
            return DevelopmentStep(message: result)
        } catch { throw normalizedProviderError(error) }
    }

    private func outputAllowance(for effort: AgentEffort, context: Int) -> Int {
        settings.maxOutputTokens ?? min(effort.developmentBudget.outputTokens, context / 2)
    }

    private func developmentCompletion(
        model: String,
        messages: [DevelopmentMessage],
        definitions: [DevelopmentToolDefinition],
        budget: VyronDevelopmentContextBudget
    ) async throws -> DevelopmentMessage {
        let tools = try definitions.map(VyronAnthropicWire.tool)
        let byteLimit = developmentMessageBudget(for: model).maximumBytes
        let messageBytes: ([DevelopmentMessage]) throws -> Int = { messages in
            let input = try VyronAnthropicWire.developmentInput(
                messages,
                model: model,
                tools: tools,
                retainingEmptyUserTurns: true
            )
            return try Self.estimatedMessageBytes(input)
        }
        let boundedBudget = VyronDevelopmentContextBudget(
            contextTokens: budget.contextTokens,
            outputTokens: budget.outputTokens,
            encodedToolBytes: try JSONEncoder().encode(tools).count,
            maximumMessageBytes: byteLimit
        )
        let input: VyronAnthropicInput
        do {
            let retained = try VyronDevelopmentRequestBudget.messages(
                messages,
                tools: definitions,
                budget: boundedBudget,
                encodedMessageBytes: messageBytes
            )
            input = try VyronAnthropicWire.developmentInput(retained, model: model, tools: tools)
        } catch DevelopmentAgentError.contextBudget {
            let retained = try VyronDevelopmentRequestBudget.byteBoundedMessages(
                messages,
                maximumMessageBytes: byteLimit,
                encodedMessageBytes: messageBytes
            )
            input = try VyronAnthropicWire.developmentInput(retained, model: model, tools: tools)
            try await verifyContext(model: model, input: input, tools: tools, budget: budget)
        }
        try await verifyTools(model: model)
        try Task.checkCancellation()
        let stream = budget.outputTokens > AgentEffort.ultra.developmentBudget.outputTokens
        let body = try VyronAnthropicWire.request(
            model: model,
            input: input,
            options: .init(maximumOutputTokens: budget.outputTokens, stream: stream, tools: tools)
        )
        let prefix = try VyronAnthropicWire.prefixDigest(input, tools: tools)
        return try await transport.completion(body, stream: stream, model: model, prefixDigest: prefix)
    }

    private static func estimatedMessageBytes(_ input: VyronAnthropicInput) throws -> Int {
        try JSONEncoder().encode(["system": input.system, "messages": input.messages]).count
    }

    private func verifyContext(
        model: String,
        input: VyronAnthropicInput,
        tools: [DevelopmentJSONValue],
        budget: VyronDevelopmentContextBudget
    ) async throws {
        let body = try VyronAnthropicWire.request(model: model, input: input, options: .init(tools: tools))
        let measured = try await transport.countInputTokens(body)
        guard measured <= budget.contextTokens - budget.outputTokens - Self.tokenCountHeadroom else {
            throw DevelopmentAgentError.contextBudget
        }
    }

    private func verifyTools(model: String) async throws {
        guard !verifiedToolModels.contains(model) else { return }
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
        let prompt = "Call vyron_check_tools with nonce \(nonce). This is a capability check only."
        let input = try VyronAnthropicWire.chatInput([ChatMessage(role: "user", content: prompt)], systemPrompt: nil)
        let body = try VyronAnthropicWire.request(
            model: model,
            input: input,
            options: .init(
                maximumOutputTokens: AgentEffort.balanced.developmentBudget.outputTokens,
                tools: [try VyronAnthropicWire.tool(probe)]
            )
        )
        let response = try await transport.completion(body, stream: false, model: model)
        guard let calls = response.toolCalls, calls.count == 1,
            calls[0].function.name == probe.function.name,
            calls[0].function.arguments == ["nonce": .string(nonce)]
        else {
            throw ModelProviderError.unsupportedTools
        }
        verifiedToolModels.insert(model)
    }
}
