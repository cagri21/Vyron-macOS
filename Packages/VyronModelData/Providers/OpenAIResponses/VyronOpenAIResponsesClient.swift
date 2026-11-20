import Foundation
import VyronLocalization
import VyronModelDomain

/// Official OpenAI Responses transport. Native workspace permissions and execution remain in Vyron's agent.
public actor VyronOpenAIResponsesClient: ModelProvider, VyronEffortChatProviding, VyronDevelopmentMessageBudgetProviding {
    private let endpoint: URL
    private let settings: ModelSettings
    private let automaticReasoning: Bool
    private let apiKey: String?
    private let session: URLSession
    private let discovery: OpenAICompatibleClient
    private let connectionID: UUID
    private let usageHandler: (@Sendable (VyronOpenAIUsageEvent) async -> Void)?
    private var verifiedToolModels: Set<String> = []

    public init(
        connection: ModelConnectionProfile,
        apiKey: String? = nil,
        usageHandler: (@Sendable (VyronOpenAIUsageEvent) async -> Void)? = nil,
        automaticReasoning: Bool = false
    ) throws {
        try self.init(
            connection: connection,
            apiKey: apiKey,
            transport: .init(configuration: .ephemeral, automaticReasoning: automaticReasoning),
            usageHandler: usageHandler
        )
    }

    init(
        connection: ModelConnectionProfile,
        apiKey: String? = nil,
        transport: VyronOpenAIResponsesTransport,
        usageHandler: (@Sendable (VyronOpenAIUsageEvent) async -> Void)? = nil
    ) throws {
        let profile = try connection.validated()
        let url = try ModelEndpoint.validated(profile.endpoint, kind: .openAICompatible)
        guard profile.kind == .openAICompatible, url.scheme == "https", url.host == "api.openai.com",
            url.port == nil || url.port == 443, url.path == "/v1"
        else { throw ModelProviderError.invalidEndpoint }
        guard profile.settings.temperature == nil, profile.settings.topP == nil else {
            throw ModelProviderError.invalidSettings(
                VyronModelDataText.openAIManagedSampling
            )
        }
        endpoint = url
        settings = profile.settings
        automaticReasoning = transport.automaticReasoning
        connectionID = profile.id
        self.usageHandler = usageHandler
        self.apiKey = try validatedModelAPIKey(apiKey)
        session = modelProviderSession(configuration: transport.configuration)
        discovery = try OpenAICompatibleClient(
            connection: profile, apiKey: apiKey, configuration: transport.configuration
        )
    }

    deinit { session.invalidateAndCancel() }

    public func models() async throws -> [LocalModel] { try await discovery.models() }

    package nonisolated func developmentMessageBudget(for model: String) -> VyronDevelopmentMessageBudget {
        VyronOpenAIResponsesModelBudget.developmentMessages(for: model)
    }

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
        _ inference: VyronChatInferenceRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let model = inference.model
        let messages = inference.messages
        let systemPrompt = inference.configuration.systemPrompt
        var usageRequest: VyronOpenAIUsageRequest?
        var parser = VyronOpenAIResponsesStream()
        do {
            try ModelEndpoint.validateModelID(model)
            let input = try VyronOpenAIResponsesWire.chatInput(messages, systemPrompt: systemPrompt)
            if messages.contains(where: { $0.images?.isEmpty == false }) {
                try await discovery.validateImageSupport(model: model)
            }
            let options = VyronOpenAIResponsesOptions(
                generation: .init(
                    maximumOutputTokens: VyronOpenAIResponsesModelBudget.outputTokens(
                        for: model,
                        requested: settings.maxOutputTokens ?? inference.configuration.effort.developmentBudget.outputTokens
                    ),
                    stream: true,
                    reasoningEffort: VyronOpenAIAutomaticReasoning.effort(
                        for: model, effort: inference.configuration.effort, enabled: automaticReasoning
                    )
                )
            )
            let body = try VyronOpenAIResponsesWire.request(
                model: model,
                input: input,
                settings: settings,
                options: options
            )
            usageRequest = VyronOpenAIUsageRequest(model: model)
            let (bytes, response) = try await session.bytes(for: request(body))
            defer { bytes.task.cancel() }
            try validate(response)
            for try await byte in bytes {
                try Task.checkCancellation()
                let token = try parser.append(byte)
                if !token.isEmpty { onToken(token) }
                if parser.completed { break }
            }
            let finalToken = try parser.finish()
            if !finalToken.isEmpty { onToken(finalToken) }
            try Task.checkCancellation()
            if let usageRequest { await reportUsage(usageRequest, response: parser.terminalResponse) }
            return parser.output
        } catch {
            if let usageRequest, !isRejectedRequest(error) {
                await reportUsage(usageRequest, response: parser.terminalResponse)
            }
            throw normalizedProviderError(error)
        }
    }

    public func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        let found: [LocalModel]
        do { found = try await models() } catch ModelProviderError.modelListUnavailable { found = [] }
        let selected = !model.isEmpty ? model : (automaticModelSelection ? found.first?.name ?? "" : "")
        try ModelEndpoint.validateModelID(selected)
        if !verifiedToolModels.contains(selected) { try await verifyTools(model: selected) }
        let local = found.first { $0.name == selected } ?? LocalModel(name: selected, size: 0)
        return LocalModel(
            name: local.name,
            size: local.size,
            parameterSize: local.parameterSize,
            quantization: local.quantization,
            capabilities: Array(Set((local.capabilities ?? []) + ["tools"])).sorted()
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

    // Stable ModelProvider interoperability requires this five-parameter signature.
    public func developmentStep(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        mode: DevelopmentMode,
        externalTools: [DevelopmentExternalTool]
    ) async throws -> DevelopmentStep {
        do {
            try ModelEndpoint.validateModelID(model)
            try VyronDevelopmentImageContext.validate(messages)
            if !verifiedToolModels.contains(model) {
                _ = try await developmentModel(model: model, automaticModelSelection: false, effort: effort)
            }
            if VyronDevelopmentImageContext.imageCount(in: messages) > 0 {
                try await discovery.validateImageSupport(model: model)
            }
            guard !messages.isEmpty else { throw DevelopmentAgentError.contextBudget }
            let tools = try DevelopmentToolDefinition.available(mode: mode, externalTools: externalTools)
            let scoped = VyronOpenAIResponsesReplay.scopedMessages(messages, model: model)
            let body = try await developmentRequest(
                model: model,
                messages: scoped,
                effort: effort,
                tools: tools
            )
            let result = try await completion(body, model: model)
            let allowed = Set(tools.map { $0.function.name })
            guard (result.message.toolCalls ?? []).allSatisfy({ allowed.contains($0.function.name) }) else {
                throw DevelopmentAgentError.invalidTool(VyronModelDataText.toolUnavailableInMode)
            }
            guard
                !hasUnfencedDevelopmentToolMarkup(result.message.content)
                    || result.message.toolCalls?.isEmpty == false
            else {
                throw DevelopmentAgentError.invalidTool(
                    VyronModelDataText.serverPrintedToolMarkup
                )
            }
            return DevelopmentStep(message: try result.continuedMessage(model: model))
        } catch { throw normalizedProviderError(error) }
    }

    private func developmentRequest(
        model: String,
        messages: [DevelopmentMessage],
        effort: AgentEffort,
        tools: [DevelopmentToolDefinition]
    ) async throws -> Data {
        let desired = VyronOpenAIResponsesModelBudget.outputTokens(
            for: model,
            requested: settings.maxOutputTokens ?? effort.developmentBudget.outputTokens
        )
        let maximumMessageBytes = developmentMessageBudget(for: model).maximumBytes
        let options = VyronOpenAIResponsesOptions(
            generation: .init(
                maximumOutputTokens: desired,
                stream: false,
                reasoningEffort: VyronOpenAIAutomaticReasoning.effort(
                    for: model, effort: effort, enabled: automaticReasoning
                )
            ),
            tools: tools
        )
        let toolBytes = try JSONEncoder().encode(tools.map(VyronOpenAIResponsesWire.tool)).count
        let encodedMessageBytes: ([DevelopmentMessage]) throws -> Int = { messages in
            try JSONEncoder().encode(VyronOpenAIResponsesReplay.input(messages, model: model)).count
        }
        var candidateMessages = messages
        do {
            candidateMessages = try VyronDevelopmentRequestBudget.messages(
                messages,
                tools: tools,
                budget: .init(
                    contextTokens: VyronOpenAIResponsesModelBudget.contextTokens(
                        for: model,
                        override: settings.contextTokens
                    ),
                    outputTokens: desired,
                    encodedToolBytes: toolBytes,
                    maximumMessageBytes: maximumMessageBytes
                ),
                encodedMessageBytes: encodedMessageBytes
            )
            let input = try VyronOpenAIResponsesReplay.input(candidateMessages, model: model)
            return try VyronOpenAIResponsesWire.request(
                model: model,
                input: input,
                settings: settings,
                options: options
            )
        } catch DevelopmentAgentError.contextBudget {
            let bounded = try VyronDevelopmentRequestBudget.byteBoundedMessages(
                candidateMessages,
                maximumMessageBytes: maximumMessageBytes,
                encodedMessageBytes: encodedMessageBytes
            )
            let input = try VyronOpenAIResponsesReplay.input(bounded, model: model)
            let body = try VyronOpenAIResponsesWire.inputTokenCountRequest(model: model, input: input, options: options)
            var countRequest = request(body)
            countRequest.url = endpoint.appendingPathComponent("responses").appendingPathComponent("input_tokens")
            let measured = try await VyronOpenAIResponsesTokenCounter(session: session, request: countRequest).count()
            try Task.checkCancellation()
            let measuredOptions = VyronOpenAIResponsesOptions(
                generation: options.generation,
                tools: tools,
                measuredInputTokens: measured
            )
            return try VyronOpenAIResponsesWire.request(
                model: model,
                input: input,
                settings: settings,
                options: measuredOptions
            )
        }
    }

    private func verifyTools(model: String) async throws {
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
        let input = [
            VyronOpenAIResponsesWire.message(
                role: "user",
                content: "Call vyron_check_tools with nonce \(nonce). This is a capability check only."
            )
        ]
        let options = VyronOpenAIResponsesOptions(
            generation: .init(
                maximumOutputTokens: min(settings.maxOutputTokens ?? 2_048, 2_048),
                stream: false,
                reasoningEffort: "low"
            ),
            tools: [probe],
            forcedTool: "vyron_check_tools"
        )
        let body = try VyronOpenAIResponsesWire.request(
            model: model,
            input: input,
            settings: settings,
            options: options
        )
        let result = try await completion(body, model: model)
        guard let calls = result.message.toolCalls, calls.count == 1,
            calls[0].function.name == "vyron_check_tools", calls[0].function.arguments == ["nonce": .string(nonce)]
        else {
            throw ModelProviderError.unsupportedTools
        }
        verifiedToolModels.insert(model)
    }

    private func completion(_ body: Data, model: String) async throws -> VyronOpenAIResponsesOutput {
        let usageRequest = VyronOpenAIUsageRequest(model: model)
        var usageResponse: DevelopmentJSONValue?
        var reported = false
        do {
            let (bytes, response) = try await session.bytes(for: request(body))
            defer { bytes.task.cancel() }
            try validate(response)
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < VyronOpenAIResponsesLimits.responseBytes else {
                    throw ModelProviderError.invalidResponse(VyronModelDataText.oversizedResponse)
                }
                data.append(byte)
            }
            usageResponse = VyronOpenAIUsageDecoding.response(data)
            await reportUsage(usageRequest, response: usageResponse)
            reported = true
            try Task.checkCancellation()
            let document = try JSONDecoder().decode(VyronOpenAIResponsesDocument.self, from: data)
            return try VyronOpenAIResponsesOutput(items: document.completedOutput())
        } catch {
            if !reported, !isRejectedRequest(error) { await reportUsage(usageRequest, response: usageResponse) }
            throw normalizedProviderError(error)
        }
    }

    private func reportUsage(_ context: VyronOpenAIUsageRequest, response: DevelopmentJSONValue?) async {
        guard let usageHandler else { return }
        await usageHandler(
            .init(
                connectionID: connectionID,
                requestID: context.id,
                startedAt: context.startedAt,
                observation: VyronOpenAIUsageDecoding.observation(
                    response,
                    model: context.model,
                    requestedSpeed: settings.responseSpeed ?? .standard
                )
            )
        )
    }

    private func isRejectedRequest(_ error: Error) -> Bool {
        if case .http(let status) = error as? ModelProviderError {
            return (400..<500).contains(status) && status != 408
        }
        return false
    }

    private func request(_ body: Data) -> URLRequest {
        var request = URLRequest(url: endpoint.appendingPathComponent("responses"))
        request.httpMethod = VyronModelHTTP.post
        request.timeoutInterval = VyronOpenAIResponsesLimits.requestTimeout
        request.setValue(VyronModelHTTP.json, forHTTPHeaderField: VyronModelHTTP.acceptHeader)
        request.setValue(VyronModelHTTP.json, forHTTPHeaderField: VyronModelHTTP.contentTypeHeader)
        if let apiKey {
            request.setValue(VyronModelHTTP.bearer(apiKey), forHTTPHeaderField: VyronModelHTTP.authorizationHeader)
        }
        request.httpBody = body
        return request
    }

    private func validate(_ response: URLResponse) throws {
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.missingHTTPResponse)
        }
        guard (200..<300).contains(http.statusCode) else { throw ModelProviderError.http(http.statusCode) }
    }
}
