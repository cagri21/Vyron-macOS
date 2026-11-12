import Foundation
import VyronLocalization
import VyronModelDomain

/// Chat Completions adapter for explicitly configured local or remote servers.
public actor OpenAICompatibleClient: ModelProvider, VyronEffortChatProviding, VyronDevelopmentMessageBudgetProviding {
    let endpoint: URL
    let settings: ModelSettings
    let connection: ModelConnectionProfile
    let apiKey: String?
    let session: URLSession
    let usageHandler: (@Sendable (VyronOpenAIUsageEvent) async -> Void)?
    var verifiedToolModels: Set<String> = []
    var usesCompletionTokenLimit = false
    var knownModelCapabilities: [String: [String]] = [:]

    public init(
        connection: ModelConnectionProfile,
        apiKey: String? = nil,
        usageHandler: (@Sendable (VyronOpenAIUsageEvent) async -> Void)? = nil
    ) throws {
        try self.init(connection: connection, apiKey: apiKey, configuration: .ephemeral, usageHandler: usageHandler)
    }

    init(
        connection: ModelConnectionProfile,
        apiKey: String? = nil,
        configuration: URLSessionConfiguration,
        usageHandler: (@Sendable (VyronOpenAIUsageEvent) async -> Void)? = nil
    ) throws {
        let profile = try connection.validated()
        guard profile.kind == .openAICompatible else { throw ModelProviderError.invalidEndpoint }
        endpoint = try ModelEndpoint.validated(profile.endpoint, kind: .openAICompatible)
        settings = profile.settings
        self.connection = profile
        self.apiKey = try validatedModelAPIKey(apiKey)
        self.usageHandler =
            endpoint.scheme == "https" && endpoint.host == "api.openai.com"
                && (endpoint.port == nil || endpoint.port == 443) && endpoint.path == "/v1" ? usageHandler : nil
        session = modelProviderSession(configuration: configuration)
    }

    deinit { session.invalidateAndCancel() }

    package nonisolated func developmentMessageBudget(for model: String) -> VyronDevelopmentMessageBudget {
        VyronDeepSeekModelBudget.published(for: connection, model: model) == nil
            ? .standard : VyronDeepSeekModelBudget.developmentMessages
    }

    public func models() async throws -> [LocalModel] {
        do {
            let request = try request(path: "models")
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.missingHTTPResponse)
            }
            if [404, 405, 501].contains(http.statusCode) { throw ModelProviderError.modelListUnavailable }
            try validate(response, data: data, maximum: 8_388_608)
            let list = try JSONDecoder().decode(VyronCompatibleModelList.self, from: data)
            var seen: Set<String> = []
            let discovered: [LocalModel] = list.data.compactMap { value in
                guard (try? ModelEndpoint.validateModelID(value.id)) != nil, seen.insert(value.id).inserted else {
                    return nil
                }
                return LocalModel(
                    name: value.id,
                    size: 0,
                    parameterSize: value.parameterSize,
                    quantization: value.quantization,
                    capabilities: value.capabilities
                )
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            knownModelCapabilities = Dictionary(
                uniqueKeysWithValues: discovered.compactMap { model in
                    model.capabilities.map { (model.name, $0) }
                }
            )
            return discovered
        } catch { throw normalizedProviderError(error) }
    }

    func validateImageSupport(model: String) throws {
        if let capabilities = knownModelCapabilities[model], !capabilities.isEmpty,
            !capabilities.contains("vision") {
            throw VyronImageAttachmentError.visionUnsupported
        }
    }

}
