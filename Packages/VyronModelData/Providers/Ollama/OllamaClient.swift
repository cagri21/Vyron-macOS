import Foundation
import VyronLocalization
import VyronModelDomain

public actor OllamaClient: ModelProvider, VyronEffortChatProviding, VyronModelThinkingControlProviding {
    private let baseURL: URL
    let session: URLSession
    let configuredConnection: Bool
    let settings: ModelSettings
    let apiKey: String?
    let imageTextPreparation: VyronImageTextPreparation
    private var thinkingSupportByModel: [String: VyronModelThinkingSupport] = [:]
    private static let maximumCachedThinkingModels = 64

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.init(baseURL: baseURL, configuration: .ephemeral)
    }

    init(baseURL: URL, configuration: URLSessionConfiguration) {
        self.init(
            baseURL: baseURL,
            configuration: configuration,
            connection: VyronOllamaConnectionSettings(isConfigured: false, model: ModelSettings(), apiKey: nil)
        )
    }

    public init(settings: ModelSettings) throws {
        try self.init(settings: settings, configuration: .ephemeral)
    }

    init(settings: ModelSettings, configuration: URLSessionConfiguration) throws {
        self.init(
            baseURL: URL(string: "http://127.0.0.1:11434")!,
            configuration: configuration,
            connection: VyronOllamaConnectionSettings(
                isConfigured: false,
                model: try settings.validated(),
                apiKey: nil
            )
        )
    }

    public init(connection: ModelConnectionProfile, apiKey: String? = nil) throws {
        try self.init(connection: connection, apiKey: apiKey, configuration: .ephemeral)
    }

    init(
        connection: ModelConnectionProfile,
        apiKey: String? = nil,
        configuration: URLSessionConfiguration,
        imageTextRecognizer: any VyronImageTextRecognizing = VyronAppleVisionTextRecognizer()
    ) throws {
        let profile = try connection.validated()
        guard profile.kind == .ollama else { throw ModelProviderError.invalidEndpoint }
        self.init(
            baseURL: try ModelEndpoint.validated(profile.endpoint, kind: .ollama),
            configuration: configuration,
            connection: VyronOllamaConnectionSettings(
                isConfigured: true,
                model: profile.settings,
                apiKey: try validatedModelAPIKey(apiKey)
            ),
            imageTextRecognizer: imageTextRecognizer
        )
    }

    private init(
        baseURL: URL,
        configuration: URLSessionConfiguration,
        connection: VyronOllamaConnectionSettings,
        imageTextRecognizer: any VyronImageTextRecognizing = VyronAppleVisionTextRecognizer()
    ) {
        self.baseURL = baseURL
        configuredConnection = connection.isConfigured
        settings = connection.model
        apiKey = connection.apiKey
        imageTextPreparation = VyronImageTextPreparation(recognizer: imageTextRecognizer)
        configuration.connectionProxyDictionary = [:]
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = VyronModelProviderSessionPolicy.requestTimeout
        configuration.timeoutIntervalForResource = VyronModelProviderSessionPolicy.resourceTimeout
        session = URLSession(configuration: configuration, delegate: ProviderRejectRedirects(), delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    public func models() async throws -> [LocalModel] {
        try await catalog(path: "tags")
            .filter {
                configuredConnection
                    ? (try? ModelEndpoint.validateModelID($0.name)) != nil
                    : (!$0.isRemote && VyronLocalModelTag.isValid($0.name))
            }
            .map(\.localModel)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func developmentModel(
        model: String,
        automaticModelSelection: Bool,
        effort: AgentEffort
    ) async throws -> LocalModel {
        try validateName(model)
        var installed = try await models()
        if configuredConnection {
            guard let selected = installed.first(where: { Self.sameModelName($0.name, model) }) else {
                throw LocalAIError.modelNotInstalled(model)
            }
            let details = try await modelMetadata(for: selected.name)
            guard details.capabilities?.contains("tools") == true else { throw ModelProviderError.unsupportedTools }
            return LocalModel(
                name: selected.name,
                size: selected.size,
                parameterSize: selected.parameterSize,
                quantization: selected.quantization,
                capabilities: details.capabilities
            )
        }
        if !automaticModelSelection,
            let index = installed.firstIndex(where: { ModelCatalog.sameInstalledName($0.name, model) }) {
            installed[index] = try await developmentModelWithCapabilities(installed[index])
        }
        return try AgentModelRouter.selectCodingModel(
            from: installed,
            selectedModel: model,
            automaticModelSelection: automaticModelSelection,
            effort: effort
        )
    }

    public func runningModels() async throws -> [LocalModel] {
        try await catalog(path: "ps")
            .filter { configuredConnection || (!$0.isRemote && VyronLocalModelTag.isValid($0.name)) }
            .map(\.localModel)
    }

    public func thinkingControlSupport(for model: LocalModel) async throws -> VyronModelThinkingSupport {
        try Task.checkCancellation()
        try validateName(model.name)
        let details = try await modelMetadata(for: model.name)
        let support = thinkingControlSupport(for: model, details: details)
        rememberThinkingSupport(support, for: model.name)
        return support
    }

    static func canonicalEndpoint(_ url: URL) throws -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
            parts.scheme?.lowercased() == VyronModelEndpointPolicy.insecureScheme,
            VyronModelEndpointPolicy.localOllamaHosts.contains(parts.host?.lowercased() ?? ""),
            parts.user == nil, parts.password == nil,
            parts.query == nil, parts.fragment == nil,
            parts.path.isEmpty || parts.path == "/",
            parts.port.map(VyronModelEndpointPolicy.validPorts.contains) ?? true
        else {
            throw LocalAIError.invalidEndpoint
        }
        parts.host = "127.0.0.1"
        parts.path = ""
        guard let endpoint = parts.url else { throw LocalAIError.invalidEndpoint }
        return endpoint
    }

    public static func validateModelName(_ name: String) throws {
        try VyronLocalModelTag.validate(name)
    }

    static func sameModelName(_ first: String, _ second: String) -> Bool {
        func normalizedName(_ name: String) -> String { name.contains(":") ? name : name + ":latest" }
        return normalizedName(first) == normalizedName(second)
    }

    func structuredThinkingOption(
        for model: LocalModel,
        effort: AgentEffort = .automatic
    ) async throws -> VyronOllamaThinkingValue? {
        // Explicit model preferences win. Effort never probes unknown controls or invents provider levels.
        if settings.thinking == nil && settings.thinkingLevel == nil {
            guard let support = thinkingSupportByModel[model.name],
                let level = VyronOllamaEffortThinking.level(for: effort, support: support)
            else { return nil }
            return .level(level)
        }
        let knownThinkingModel = isKnownThinkingModel(model)
        if let capabilities = model.capabilities, !capabilities.contains("thinking"),
            !knownThinkingModel, !hasCachedThinkingControls(for: model.name) {
            return nil
        }
        let details = try await modelMetadata(for: model.name)
        let values = details.thinking?.values ?? []
        if let requested = settings.thinkingLevel {
            return values.contains(.level(requested.rawValue)) ? .level(requested) : nil
        }
        guard let requested = settings.thinking else { return nil }
        switch thinkingControlSupport(for: model, details: details) {
        case .boolean:
            return .toggle(VyronOllamaThinkingToggle(requested))
        case .levels(let support):
            let accepted = requested ? support.supportsOn : support.supportsOff
            return accepted ? .toggle(VyronOllamaThinkingToggle(requested)) : nil
        case .providerDefaultOnly:
            // Keep the saved preference without guessing how it maps to a named level.
            return values.contains(.boolean(requested)) ? .toggle(VyronOllamaThinkingToggle(requested)) : nil
        case .unsupported, .unverified:
            return nil
        }
    }

    func structuredOutputTokens(
        model: LocalModel,
        thinking: VyronOllamaThinkingValue?,
        budget: VyronOllamaStructuredOutputBudget
    ) throws -> Int {
        let reasoningMayRun: Bool
        switch thinking {
        case .toggle(.disabled): reasoningMayRun = false
        case .toggle(.enabled), .level: reasoningMayRun = true
        case nil:
            switch thinkingSupportByModel[model.name] {
            case .boolean, .providerDefaultOnly: reasoningMayRun = true
            case .levels(let controls): reasoningMayRun = controls.hasControls
            case .unsupported: reasoningMayRun = false
            case .unverified, nil:
                reasoningMayRun = model.capabilities?.contains("thinking") == true || isKnownThinkingModel(model)
            }
        }
        return try budget.resolved(reasoningMayRun: reasoningMayRun, maximumOutputTokens: settings.maxOutputTokens)
    }

    private func rememberThinkingSupport(_ support: VyronModelThinkingSupport, for model: String) {
        if thinkingSupportByModel[model] == nil, thinkingSupportByModel.count >= Self.maximumCachedThinkingModels {
            thinkingSupportByModel.removeAll(keepingCapacity: true)
        }
        thinkingSupportByModel[model] = support
    }

    private func hasCachedThinkingControls(for model: String) -> Bool {
        switch thinkingSupportByModel[model] {
        case .boolean: true
        case .levels(let controls): controls.hasControls
        case .providerDefaultOnly, .unverified, .unsupported, nil: false
        }
    }

    private func thinkingControlSupport(
        for model: LocalModel,
        details: VyronOllamaModelShowResponse
    ) -> VyronModelThinkingSupport {
        if let values = details.thinking?.values, !values.isEmpty {
            let levels = VyronModelThinkingLevel.allCases.filter { values.contains(.level($0.rawValue)) }
            let supportsOn = values.contains(.boolean(true))
            let supportsOff = values.contains(.boolean(false))
            if levels.isEmpty, supportsOn, supportsOff { return .boolean }
            if !levels.isEmpty || supportsOn || supportsOff {
                return .levels(
                    VyronModelThinkingLevels(
                        levels: levels,
                        supportsOn: supportsOn,
                        supportsOff: supportsOff
                    )
                )
            }
            return .providerDefaultOnly
        }
        // Older Ollama metadata advertises thinking without the newer values object.
        let hasThinking =
            details.capabilities?.contains("thinking")
            ?? (model.capabilities?.contains("thinking") ?? isKnownThinkingModel(model))
        return hasThinking ? .boolean : .unsupported
    }

    private func isKnownThinkingModel(_ model: LocalModel) -> Bool {
        let leafName = String(model.name.split(separator: "/").last ?? "").lowercased()
        return ModelCatalog.descriptor(for: model.name)?.supportsThinking == true
            || leafName == "qwen3" || leafName.hasPrefix("qwen3:")
            || leafName.hasPrefix("qwen3.8:") || leafName.hasPrefix("qwen3.6:")
    }

    func developmentModelWithCapabilities(_ model: LocalModel) async throws -> LocalModel {
        guard ModelCatalog.descriptor(for: model.name) == nil,
            model.capabilities?.isEmpty != false
        else { return model }
        let details = try await modelMetadata(for: model.name)
        return LocalModel(
            name: model.name,
            size: model.size,
            parameterSize: model.parameterSize,
            quantization: model.quantization,
            capabilities: details.capabilities
        )
    }

    func requestedContext(for model: LocalModel, fallback: Int) async throws -> Int {
        guard let requested = settings.contextTokens else { return fallback }
        let details = try await modelMetadata(for: model.name)
        if let supported = details.maximumContextTokens, requested > supported {
            throw ModelProviderError.invalidSettings(
                VyronModelDataText.ollamaMaximumContext(String(supported))
            )
        }
        return requested
    }

    func modelMetadata(for model: String) async throws -> VyronOllamaModelShowResponse {
        var request = try makeRequest(path: "show", body: VyronOllamaModelShowRequest(model: model))
        request.timeoutInterval = VyronOllamaTransportLimits.metadataTimeout
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw LocalAIError.invalidResponse(VyronModelDataText.missingModelMetadataResponse)
            }
            guard (200..<300).contains(http.statusCode) else { throw httpError(http.statusCode, data: data) }
            guard data.count <= VyronOllamaTransportLimits.maximumMetadataBytes else {
                throw LocalAIError.invalidResponse(VyronModelDataText.modelMetadataTooLarge)
            }
            let details = try JSONDecoder().decode(VyronOllamaModelShowResponse.self, from: data)
            guard
                configuredConnection || ((details.remote_model ?? "").isEmpty && (details.remote_host ?? "").isEmpty)
            else { throw LocalAIError.cloudModelNotAllowed }
            rememberThinkingSupport(
                thinkingControlSupport(for: LocalModel(name: model, size: 0), details: details),
                for: model
            )
            return details
        } catch {
            throw Self.normalized(error)
        }
    }

    func catalog(path: String) async throws -> [VyronOllamaModelPayload] {
        let endpoint = try connectionEndpoint()
        var request = URLRequest(url: endpoint.appendingPathComponent("api").appendingPathComponent(path))
        if let apiKey {
            request.setValue(VyronModelHTTP.bearer(apiKey), forHTTPHeaderField: VyronModelHTTP.authorizationHeader)
        }
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw LocalAIError.invalidResponse(VyronModelDataText.missingHTTPResponse)
            }
            guard (200..<300).contains(http.statusCode) else {
                throw httpError(http.statusCode, data: data)
            }
            guard data.count <= VyronOllamaTransportLimits.maximumCatalogBytes else {
                throw LocalAIError.invalidResponse(VyronModelDataText.modelListTooLarge)
            }
            do {
                return try JSONDecoder().decode(VyronOllamaModelList.self, from: data).models
            } catch {
                throw LocalAIError.invalidResponse(VyronModelDataText.malformedModelList)
            }
        } catch {
            throw Self.normalized(error)
        }
    }

    func connectionEndpoint() throws -> URL {
        try configuredConnection
            ? ModelEndpoint.validated(baseURL.absoluteString, kind: .ollama) : Self.canonicalEndpoint(baseURL)
    }

    func validateName(_ name: String) throws {
        if configuredConnection { try ModelEndpoint.validateModelID(name) } else { try Self.validateModelName(name) }
    }
}
