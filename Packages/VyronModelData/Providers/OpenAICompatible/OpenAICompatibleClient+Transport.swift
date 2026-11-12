import Foundation
import VyronLocalization
import VyronModelDomain

extension OpenAICompatibleClient {
    func configured(
        _ body: VyronCompatibleChatRequest,
        effort: AgentEffort,
        isProbe: Bool = false
    ) -> VyronCompatibleChatRequest {
        guard VyronDeepSeekRoute.matches(connection) else { return body }
        var configured = body
        let options = VyronDeepSeekRequestConfiguration(
            settings: isProbe ? ModelSettings(thinking: false) : settings,
            effort: effort
        )
        configured.deepSeek = options
        if options.enabled { configured.temperature = nil }
        return configured
    }

    func requestedBudget(limits: VyronDeepSeekModelBudget?, effort: AgentEffort) throws -> VyronDevelopmentContextBudget {
        // A per-call model ID may differ from the model used to validate the saved profile.
        let effective = limits == nil ? try settings.validated() : settings
        let messageBudget = limits == nil ? .standard : VyronDeepSeekModelBudget.developmentMessages
        return VyronDevelopmentContextBudget(
            contextTokens: effective.contextTokens ?? limits?.contextTokens ?? 32_768,
            outputTokens: effective.maxOutputTokens ?? effort.developmentBudget.outputTokens,
            maximumMessageBytes: messageBudget.maximumBytes
        )
    }

    func outputBudget(
        messages: [VyronCompatibleMessage],
        tools: [DevelopmentToolDefinition],
        budget: VyronDevelopmentContextBudget,
        minimum: Int
    ) throws -> Int {
        // Conservatively bound input tokens by UTF-8 bytes; do not advertise more context than is budgeted.
        let textMessages = messages.map { message in
            var text = message
            text.images = nil
            return text
        }
        let imageCount = messages.reduce(0) { $0 + ($1.images?.count ?? 0) }
        let input =
            try JSONEncoder().encode(textMessages).count + JSONEncoder().encode(tools).count
            + VyronDevelopmentRequestBudget.requestOverheadTokens
            + imageCount * VyronImageAttachment.estimatedContextTokens
        let output = min(budget.outputTokens, budget.contextTokens - input)
        guard output >= minimum else { throw DevelopmentAgentError.contextBudget }
        return output
    }

    func completion(_ body: VyronCompatibleChatRequest) async throws -> VyronCompatibleCompletion {
        let usageRequest = VyronOpenAIUsageRequest(model: body.model)
        var reported = false
        var attempted = false
        let maximum = VyronDeepSeekRoute.matches(connection) ? VyronDeepSeekReplayScope.maximumResponseBytes : 131_072
        do {
            for attempt in 0..<2 {
                var request = try request(path: "chat/completions", body: body)
                request.timeoutInterval = 180
                attempted = true
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                    data.count <= maximum {
                    // A complete body can arrive before cancellation resumes this actor.
                    // Keep its trustworthy billing usage even when the answer is no longer needed.
                    await reportUsage(usageRequest, response: VyronOpenAIUsageDecoding.response(data))
                    reported = true
                }
                try Task.checkCancellation()
                if attempt == 0, let http = response as? HTTPURLResponse,
                    [400, 422].contains(http.statusCode), !usesCompletionTokenLimit,
                    data.count <= 16_384, requestsCompletionTokenLimit(data) {
                    usesCompletionTokenLimit = true
                    continue
                }
                try validate(response, data: data, maximum: maximum)
                return try JSONDecoder().decode(VyronCompatibleCompletion.self, from: data)
            }
            throw ModelProviderError.invalidResponse(VyronModelDataText.serverRejectedOutputLimit)
        } catch {
            if attempted, !reported, !isRejectedUsageRequest(error) {
                await reportUsage(usageRequest, response: nil)
            }
            throw normalizedProviderError(error)
        }
    }

    func reportUsage(_ context: VyronOpenAIUsageRequest, response: DevelopmentJSONValue?) async {
        guard let usageHandler else { return }
        await usageHandler(
            .init(
                connectionID: connection.id,
                requestID: context.id,
                startedAt: context.startedAt,
                observation: VyronOpenAIUsageDecoding.observation(
                    response,
                    model: context.model,
                    compatible: true,
                    requestedSpeed: settings.responseSpeed ?? .standard
                )
            )
        )
    }

    func isRejectedUsageRequest(_ error: Error) -> Bool {
        if case .http(let status) = error as? ModelProviderError {
            return (400..<500).contains(status) && status != 408
        }
        return false
    }

    /// A narrow retry of rejected inference data; never repeats an executed workspace action.
    func requestsCompletionTokenLimit(_ data: Data) -> Bool {
        guard let value = try? JSONDecoder().decode(DevelopmentJSONValue.self, from: data),
            case .object(let envelope) = value, case .object(let error) = envelope["error"],
            case .string(let message) = error["message"]
        else { return false }
        let detail = message.lowercased()
        return detail.contains("max_tokens") && detail.contains("max_completion_tokens")
            && (detail.contains("unsupported") || detail.contains("not supported")
                || detail.contains("use 'max_completion_tokens'"))
    }

    func request(path: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint.appendingPathComponent(path))
        request.setValue(VyronModelHTTP.json, forHTTPHeaderField: VyronModelHTTP.acceptHeader)
        if let apiKey {
            request.setValue(VyronModelHTTP.bearer(apiKey), forHTTPHeaderField: VyronModelHTTP.authorizationHeader)
        }
        return request
    }

    func request<Body: Encodable>(path: String, body: Body) throws -> URLRequest {
        var result = try request(path: path)
        result.httpMethod = VyronModelHTTP.post
        result.setValue(VyronModelHTTP.json, forHTTPHeaderField: VyronModelHTTP.contentTypeHeader)
        result.httpBody = try JSONEncoder().encode(body)
        if VyronConnectionBalancePolicy.support(for: connection) == .dashboardOnly,
            let data = result.httpBody,
            var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let model = object["model"] as? String {
            object["service_tier"] = VyronOpenAIResponseSpeed.serviceTier(settings: settings, model: model)
            result.httpBody = try JSONSerialization.data(withJSONObject: object)
        }
        if usageHandler != nil, let data = result.httpBody,
            var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["stream"] as? Bool == true {
            object["stream_options"] = ["include_usage": true]
            result.httpBody = try JSONSerialization.data(withJSONObject: object)
        }
        if usesCompletionTokenLimit, let data = result.httpBody,
            var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let maximum = object.removeValue(forKey: "max_tokens") {
            object["max_completion_tokens"] = maximum
            result.httpBody = try JSONSerialization.data(withJSONObject: object)
        }
        return result
    }

    func validate(_ response: URLResponse, data: Data, maximum: Int) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.missingHTTPResponse)
        }
        guard (200..<300).contains(http.statusCode) else { throw ModelProviderError.http(http.statusCode) }
        guard data.count <= maximum else { throw ModelProviderError.invalidResponse(VyronModelDataText.responseTooLarge) }
    }
}
