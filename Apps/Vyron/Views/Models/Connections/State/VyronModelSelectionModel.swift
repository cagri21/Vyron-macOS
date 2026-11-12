import Combine
import Foundation
import VyronModelData
import VyronModelDomain

@MainActor
final class VyronModelSelectionModel: ObservableObject {
    @Published var models: [LocalModel] = []
    @Published var selectedModel: String {
        didSet {
            if isBuiltinConnection { preferences.model = selectedModel }
            if selectedModel != oldValue { selectionChanged?() }
        }
    }
    @Published var automaticModelSelection: Bool {
        didSet {
            if isBuiltinConnection { preferences.automaticallySelect = automaticModelSelection }
        }
    }
    @Published var connectionProfiles: [ModelConnectionProfile] = []
    @Published var activeConnectionID: UUID?
    @Published var builtinModelSettings = ModelSettings()
    @Published var connectionOperationInProgress = false
    @Published var connectionStatus: String?
    @Published var connectionError: String?
    @Published var isConnected = false
    @Published var isRefreshing = false
    @Published var isStarting = false

    var configuredInferenceClient: (any ModelProvider)?
    var connectionRevision = UUID()
    var modelConnectionsWritable = true
    var selectionChanged: (@MainActor () -> Void)?
    private(set) var builtinClient: OllamaClient

    let store: ModelConnectionStore
    let preferences: VyronBuiltinModelPreferences
    private let providers: VyronModelProviderBuilders
    private var refreshTask: Task<Void, Never>?
    private var stopped = false

    init(
        builtinClient: OllamaClient,
        store: ModelConnectionStore,
        preferences: VyronBuiltinModelPreferences,
        providers: VyronModelProviderBuilders
    ) {
        self.builtinClient = builtinClient
        self.store = store
        self.preferences = preferences
        self.providers = providers
        selectedModel = preferences.model
        automaticModelSelection = preferences.automaticallySelect
    }

    var inferenceProvider: (any ModelProvider)? {
        configuredInferenceClient ?? (isBuiltinConnection ? builtinClient : nil)
    }

    var isBuiltinConnection: Bool { activeConnectionID == nil }

    var activeConnectionProfile: ModelConnectionProfile? {
        connectionProfiles.first { $0.id == activeConnectionID }
    }

    var activeConnectionName: String { activeConnectionProfile?.name ?? VyronWorkspaceText.thisMac }

    var activeConnectionIsLocal: Bool {
        guard let profile = activeConnectionProfile else { return true }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(
            URL(string: profile.endpoint)?.host?.lowercased() ?? ""
        )
    }

    var inferenceLocationLabel: String {
        isBuiltinConnection
            ? VyronWorkspaceText.thisMac
            : activeConnectionIsLocal ? VyronStatusText.localServer : VyronStatusText.remoteServer
    }

    var connectionLabel: String {
        if isStarting { return VyronStatusText.startingEngine }
        if isRefreshing { return VyronStatusText.checkingConnection }
        return isConnected
            ? VyronStatusText.connectionConnected(activeConnectionName)
            : VyronStatusText.connectionOffline(activeConnectionName)
    }

    var connectionState: ModelConnectionState {
        ModelConnectionState(
            profiles: connectionProfiles,
            activeConnectionID: activeConnectionID,
            builtinSettings: builtinModelSettings
        )
    }

    var builtinActivation: VyronModelConnectionActivation {
        VyronModelConnectionActivation(
            id: nil,
            provider: nil,
            model: preferences.model,
            automaticallySelect: preferences.automaticallySelect
        )
    }

    var modelIsAvailable: Bool { models.contains { modelNamesMatch($0.name, selectedModel) } }

    func modelNamesMatch(_ first: String, _ second: String) -> Bool {
        if let connection = activeConnectionProfile, connection.kind != .ollama { return first == second }
        return ModelCatalog.sameInstalledName(first, second)
    }

    func installedModel(for descriptor: ModelDescriptor) -> LocalModel? {
        let associated = models.filter { ModelCatalog.descriptor(for: $0.name)?.id == descriptor.id }
        if !automaticModelSelection,
            let selected = associated.first(where: { ModelCatalog.sameInstalledName($0.name, selectedModel) }) {
            return selected
        }
        return models.first { ModelCatalog.sameInstalledName($0.name, descriptor.tag) } ?? associated.first
    }

    func isSelectedModel(_ name: String) -> Bool {
        !automaticModelSelection && modelNamesMatch(selectedModel, name)
    }

    func selectInstalledModel(_ name: String) throws -> LocalModel {
        guard let installed = models.first(where: { modelNamesMatch($0.name, name) }) else {
            throw ModelProviderError.invalidSettings(VyronStatusText.downloadBeforeSelecting)
        }
        if let id = activeConnectionID, let index = connectionProfiles.firstIndex(where: { $0.id == id }) {
            var saved = connectionState
            saved.profiles[index].selectedModel = installed.name
            try persist(saved)
            connectionProfiles = saved.profiles
        }
        selectedModel = installed.name
        automaticModelSelection = false
        return installed
    }

    func useAutomaticSelection(forChat: Bool) throws {
        automaticModelSelection = true
        let candidate =
            if forChat {
                AgentModelRouter.selectModel(from: models, preferredModel: selectedModel, effort: .balanced)
            } else {
                try? AgentModelRouter.selectCodingModel(
                    from: models,
                    selectedModel: selectedModel,
                    automaticModelSelection: true,
                    effort: .balanced
                )
            }
        guard let candidate else { throw VyronAutomaticModelSelectionError() }
        selectedModel = candidate.name
    }

    func load() {
        let saved: ModelConnectionState
        do {
            saved = try store.load()
        } catch {
            modelConnectionsWritable = false
            connectionError = VyronStatusText.savedConnectionsUnavailable(error.localizedDescription)
            return
        }
        connectionProfiles = saved.profiles
        builtinModelSettings = saved.builtinSettings
        activeConnectionID = saved.activeConnectionID
        do {
            if builtinModelSettings != ModelSettings() { builtinClient = try providers.builtin(builtinModelSettings) }
            if let profile = activeConnectionProfile {
                selectedModel = profile.selectedModel
                automaticModelSelection = false
            }
        } catch {
            connectionError = VyronStatusText.activeConnectionUnavailable(error.localizedDescription)
        }
    }

    func persist(_ state: ModelConnectionState) throws {
        guard modelConnectionsWritable else {
            throw ModelProviderError.invalidSettings(VyronStatusText.connectionStorageRecovery)
        }
        try store.save(state)
    }

    func makeProvider(for profile: ModelConnectionProfile, apiKey: String) throws -> any ModelProvider {
        try providers.configured(profile, apiKey)
    }

    func prepareActiveConnection(
        readKey: @Sendable (UUID) async throws -> String,
        canApply: @MainActor () -> Bool
    ) async {
        guard let profile = activeConnectionProfile, configuredInferenceClient == nil,
            canApply(), !stopped, !Task.isCancelled
        else { return }
        let revision = connectionRevision
        do {
            let key = try await readKey(profile.id)
            guard canApply(), isCurrentPreparation(profile: profile, revision: revision) else { return }
            configuredInferenceClient = try makeProvider(for: profile, apiKey: key)
            connectionError = nil
        } catch is CancellationError {
            return
        } catch {
            guard canApply(), isCurrentPreparation(profile: profile, revision: revision) else { return }
            connectionError = VyronStatusText.activeConnectionUnavailable(error.localizedDescription)
        }
    }

    func activate(_ activation: VyronModelConnectionActivation) {
        renewConnectionRevision()
        activeConnectionID = activation.id
        configuredInferenceClient = activation.provider
        isConnected = false
        models = []
        selectedModel = activation.model
        automaticModelSelection = activation.automaticallySelect
        connectionError = nil
    }

    func applyBuiltinSettings(_ requested: ModelSettings) throws {
        let settings = try requested.validated()
        let updated = try providers.builtin(settings)
        var saved = connectionState
        saved.builtinSettings = settings
        try persist(saved)
        builtinModelSettings = settings
        builtinClient = updated
        renewConnectionRevision()
    }

    func replaceConfiguredProvider(_ provider: any ModelProvider, profiles: [ModelConnectionProfile]) {
        renewConnectionRevision()
        configuredInferenceClient = provider
        connectionProfiles = profiles
    }

    func refreshCatalog() async -> VyronModelCatalogRefresh {
        guard !stopped, !isRefreshing else { return .unchanged }
        guard let provider = inferenceProvider else {
            isConnected = false
            models = []
            return .unchanged
        }
        let revision = connectionRevision
        isRefreshing = true
        defer { if connectionRevision == revision { isRefreshing = false } }
        do {
            let discovered: [LocalModel]
            do { discovered = try await provider.models() } catch ModelProviderError.modelListUnavailable {
                guard !isBuiltinConnection, !selectedModel.isEmpty else {
                    throw ModelProviderError.modelListUnavailable
                }
                discovered = [LocalModel(name: selectedModel, size: 0)]
            }
            guard connectionRevision == revision, !stopped, !Task.isCancelled else { return .unchanged }
            models =
                discovered
                .filter { !isBuiltinConnection || !$0.name.lowercased().contains("cloud") }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if !isBuiltinConnection, !selectedModel.isEmpty, !modelIsAvailable {
                // Preserve exact manually verified IDs when the server omits them from discovery.
                models.append(LocalModel(name: selectedModel, size: 0))
            }
            isConnected = true
            if isBuiltinConnection, automaticModelSelection, !modelIsAvailable {
                let candidates = models.filter {
                    ModelCatalog.descriptor(for: $0.name)?.isAutomaticCodingCandidate ?? true
                }
                if let recommended = candidates.first(where: {
                    modelNamesMatch($0.name, ModelCatalog.recommendedCodingTag)
                }) ?? candidates.first {
                    selectedModel = recommended.name
                }
            }
            return .loaded
        } catch {
            guard connectionRevision == revision, !stopped, !Task.isCancelled else { return .unchanged }
            isConnected = false
            models = []
            return .failed(VyronModelCatalogFailure(detail: error.localizedDescription))
        }
    }

    func startPeriodicRefresh(_ refresh: @escaping @MainActor () async -> Void) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                guard self?.stopped == false else { return }
                await refresh()
            }
        }
    }

    func shutdown() {
        stopped = true
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func renewConnectionRevision() {
        connectionRevision = UUID()
        isRefreshing = false
    }

    private func isCurrentPreparation(profile: ModelConnectionProfile, revision: UUID) -> Bool {
        !stopped && !Task.isCancelled && connectionRevision == revision
            && activeConnectionProfile == profile && configuredInferenceClient == nil
    }
}
