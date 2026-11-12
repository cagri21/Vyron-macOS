import Foundation
import OSLog
import VyronLocalization
import VyronModelDomain

extension OllamaClient: VyronDevelopmentInferenceProviding {
    private static let inferenceLogger = Logger(subsystem: "ai.vyron.desktop", category: "Development inference")

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
        do {
            return try await developmentInference(
                VyronDevelopmentInferenceRequest(
                    model: model,
                    messages: messages,
                    configuration: VyronDevelopmentInferenceConfiguration(
                        effort: effort,
                        mode: mode,
                        externalTools: externalTools
                    )
                )
            )
        } catch let failure as VyronDevelopmentReplyFailure {
            throw failure.originalError
        }
    }

    package func developmentInference(_ input: VyronDevelopmentInferenceRequest) async throws -> DevelopmentStep {
        let model = input.model
        var messages = Self.messagesWithoutContinuation(input.messages)
        let effort = input.configuration.effort
        let mode = input.configuration.mode
        let externalTools = input.configuration.externalTools
        try validateName(model)
        try VyronDevelopmentImageContext.validate(messages)
        guard !messages.isEmpty, messages.allSatisfy({ ["system", "user", "assistant", "tool"].contains($0.role) })
        else { throw DevelopmentAgentError.contextBudget }
        let installed = try await catalog(path: "tags")
        guard let selected = installed.first(where: { Self.sameModelName($0.name, model) }) else {
            throw LocalAIError.modelNotInstalled(model)
        }
        guard configuredConnection || !selected.isRemote else { throw LocalAIError.cloudModelNotAllowed }
        let localModel = try await developmentModelWithCapabilities(selected.localModel)
        if VyronDevelopmentImageContext.imageCount(in: messages) > 0 {
            let capabilities: [String]?
            if let advertised = localModel.capabilities, !advertised.isEmpty {
                capabilities = advertised
            } else {
                capabilities = try await modelMetadata(for: selected.name).capabilities
            }
            if capabilities?.contains("vision") != true {
                messages = try await imageTextPreparation.developmentMessages(messages)
            }
        }
        try Task.checkCancellation()
        if configuredConnection {
            let details = try await modelMetadata(for: selected.name)
            guard details.capabilities?.contains("tools") == true else { throw ModelProviderError.unsupportedTools }
        } else if let reason = ModelCatalog.codingIncompatibilityReason(for: localModel) {
            throw DevelopmentAgentError.unsupportedModel("\(selected.name): \(reason)")
        }
        let thinking = try await structuredThinkingOption(for: localModel, effort: effort)
        let tools = try DevelopmentToolDefinition.available(mode: mode, externalTools: externalTools)
        var requestMessages = developmentMessagesWithToolProtocol(messages, model: selected.name)
        var repairContext: Int?
        do {
            for attempt in 0..<2 {
                try Task.checkCancellation()
                let maximumContext = try await requestedContext(
                    for: localModel,
                    fallback: ModelCatalog.descriptor(for: selected.name)?.recommendedContextTokens ?? 32_768
                )
                requestMessages = try VyronDevelopmentRequestBudget.messages(
                    requestMessages,
                    tools: tools,
                    budget: .init(contextTokens: repairContext ?? min(maximumContext, settings.contextTokens ?? 32_768))
                )
                var options = try developmentRequestOptions(
                    messages: requestMessages,
                    tools: tools,
                    effort: effort,
                    limits: .init(
                        maximumContext: maximumContext,
                        contextOverride: repairContext ?? settings.contextTokens,
                        outputOverride: settings.maxOutputTokens
                    )
                )
                let messageBytes = try VyronDevelopmentImageContext.estimatedMessageBytes(requestMessages)
                let schemaBytes = try JSONEncoder().encode(tools).count
                let output = try structuredOutputTokens(
                    model: localModel,
                    thinking: thinking,
                    budget: VyronOllamaStructuredOutputBudget(
                        outputTokens: options.num_predict,
                        contextTokens: options.num_ctx,
                        inputBytes: messageBytes + schemaBytes
                    )
                )
                options = .init(num_ctx: options.num_ctx, num_predict: output)
                options.temperature = settings.temperature ?? 0.1; options.top_p = settings.topP
                guard options.num_predict >= 512 else { throw DevelopmentAgentError.contextBudget }
                var request = try makeRequest(
                    path: "chat",
                    body: DevelopmentStepRequest(
                        model: model,
                        messages: requestMessages.map { VyronOllamaDevelopmentMessage(message: $0) },
                        think: thinking,
                        tools: tools,
                        options: options
                    )
                )
                request.timeoutInterval = VyronOllamaTransportLimits.structuredInferenceTimeout
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse else {
                    throw LocalAIError.invalidResponse(VyronModelDataText.missingHTTPResponse)
                }
                guard (200..<300).contains(http.statusCode) else { throw httpError(http.statusCode, data: data) }
                guard data.count <= 131_072 else {
                    throw DevelopmentAgentError.invalidTool(VyronModelDataText.toolResponseTooLarge)
                }
                let reply = try JSONDecoder().decode(DevelopmentStepResponse.self, from: data)
                if let error = reply.error { throw serverError(error) }
                guard reply.done == true, let message = reply.message, message.role == "assistant" else {
                    throw LocalAIError.incompleteStream
                }
                guard (message.toolCalls?.count ?? 0) <= 4 else {
                    throw DevelopmentAgentError.invalidTool(VyronModelDataText.tooManyToolCalls)
                }
                if let issue = VyronOllamaDevelopmentReplyIssue(reply: reply) {
                    let diagnostic = VyronOllamaReplyDiagnostic(
                        attempt: attempt + 1,
                        issue: issue,
                        request: VyronOllamaRequestMetrics(
                            contextTokens: options.num_ctx,
                            outputTokens: options.num_predict,
                            messageBytes: messageBytes,
                            schemaBytes: schemaBytes
                        ),
                        response: VyronOllamaResponseMetrics.decode(data: data, reason: reply.doneReason)
                    )
                    Self.inferenceLogger.warning("\(diagnostic.summary, privacy: .public)")
                    guard attempt == 0, issue.canRepair else {
                        if issue.canRepair {
                            throw VyronDevelopmentReplyFailure(
                                originalError: .invalidResponse(issue.errorDetail),
                                diagnostic: diagnostic
                            )
                        }
                        throw LocalAIError.invalidResponse(issue.errorDetail)
                    }
                    try Task.checkCancellation()
                    requestMessages = issue.repairMessages(requestMessages)
                    repairContext = options.num_ctx
                    try Task.checkCancellation()
                    continue
                }
                if (message.toolCalls ?? []).isEmpty, hasUnfencedDevelopmentToolMarkup(message.content) {
                    guard attempt == 0 else {
                        throw DevelopmentAgentError.invalidTool(
                            VyronModelDataText.repeatedToolMarkup
                        )
                    }
                    let familyGrammar =
                        developmentUsesFunctionXMLGrammar(selected.name)
                        ? " For Qwen3-Coder, the complete <function=...> block MUST be nested inside BOTH <tool_call> and </tool_call>; omitting the opening wrapper turns the function into ordinary text."
                        : " Use this selected model's own runtime tool-call format; do not copy another model family's XML grammar."
                    requestMessages.append(
                        DevelopmentMessage(
                            role: "user",
                            content: """
                    The previous response printed a bare function block in assistant text, but the API returned no native tool_calls. No actual tool call was executed. Continue the SAME original task and obey the exact function-call grammar in the runtime's Tools section, including every required outer tool-call delimiter.\(familyGrammar) Do not emit a bare inner function block. Only API tool_calls are executable; no printed text will be parsed into actions. All original scope, Plan-mode restrictions and command review requirements remain unchanged. If you are explaining an illustrative example rather than requesting a tool, put that example inside a fenced code block. Do not claim the printed request ran.
                    """
                        )
                    )
                    continue
                }
                return DevelopmentStep(message: message)
            }
            throw DevelopmentAgentError.invalidTool(VyronModelDataText.noUsableToolResponse)
        } catch { throw Self.normalized(error) }
    }
}
