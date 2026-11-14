import Foundation
import VyronModelData
import VyronModelDomain

extension AppModel {
    func savedAPIKey(for id: UUID) throws -> String { try modelCredentialStore.key(for: id) }

    func discoverConnectionModels(profile: ModelConnectionProfile, apiKey: String) async throws -> [LocalModel] {
        guard canManageModelSelection, !modelDownloads.isActive else { throw modelConnectionBusyError }
        modelSelection.connectionOperationInProgress = true
        defer { modelSelection.connectionOperationInProgress = false }
        let provider = try modelSelection.makeProvider(for: profile.validated(), apiKey: apiKey)
        let discovered = try await provider.models()
        try Task.checkCancellation()
        guard !isShuttingDown else { throw CancellationError() }
        return discovered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func testConnection(profile: ModelConnectionProfile, apiKey: String) async throws -> String {
        guard canManageModelSelection, !modelDownloads.isActive else { throw modelConnectionBusyError }
        modelSelection.connectionOperationInProgress = true
        defer { modelSelection.connectionOperationInProgress = false }
        let profile = try profile.validated()
        try ModelEndpoint.validateModelID(profile.selectedModel)
        let provider = try modelSelection.makeProvider(for: profile, apiKey: apiKey)
        let selection = modelFeatureSelection(for: profile)
        try await verifyModelResponse(provider: provider, model: profile.selectedModel)
        let verification = try await verifyConnectionFeatures(provider: provider, selection: selection)
        if verification == .verified { return VyronStatusText.agentConnectionVerified }
        let report = modelFeatureReport(for: profile)
        let detail =
            VyronModelFeaturePresentation.reason(report[.agent].reason)
            ?? VyronAppText.modelFeaturesCheckTools
        return VyronStatusText.chatConnectionVerified(detail)
    }

    func saveConnection(_ requested: ModelConnectionProfile, apiKey: String) async throws {
        guard canManageModelSelection, !modelDownloads.isActive else { throw modelConnectionBusyError }
        localAuthentication.invalidate(connectionID: requested.id)
        modelSelection.connectionOperationInProgress = true
        defer {
            modelSelection.connectionOperationInProgress = false
            requestModelFeatureVerification()
        }
        let profile = try requested.validated()
        try ModelEndpoint.validateModelID(profile.selectedModel)
        let provider = try modelSelection.makeProvider(for: profile, apiKey: apiKey)
        let selection = modelFeatureSelection(for: profile)
        try await verifyModelResponse(provider: provider, model: profile.selectedModel)
        _ = try await verifyConnectionFeatures(provider: provider, selection: selection)
        try Task.checkCancellation()
        guard !isShuttingDown else { throw CancellationError() }
        var profiles = modelSelection.connectionProfiles
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        let oldKey = try savedAPIKey(for: profile.id)
        try modelCredentialStore.setKey(apiKey, for: profile.id)
        var saved = modelSelection.connectionState
        saved.profiles = profiles
        do { try modelSelection.persist(saved) } catch {
            try? modelCredentialStore.setKey(oldKey, for: profile.id)
            throw error
        }
        modelSelection.connectionProfiles = profiles
        requestLocalCredentialSynchronization()
        if oldKey != apiKey.trimmingCharacters(in: .whitespacesAndNewlines) {
            connectionBalances.credentialChanged(profile.id)
        }
        modelSelection.connectionError = nil
        modelSelection.connectionStatus = VyronStatusText.connectionSaved(profile.name)
        if modelSelection.activeConnectionID == profile.id {
            await switchInferenceConnection(
                VyronModelConnectionActivation(
                    id: profile.id,
                    provider: provider,
                    model: profile.selectedModel,
                    automaticallySelect: false
                )
            )
            retainConnectionFeatureVerification(from: selection)
        }
    }

    func activateConnection(_ id: UUID?) async {
        guard canManageModelSelection, !modelDownloads.isActive else {
            modelSelection.connectionError = modelConnectionBusyError.localizedDescription
            return
        }
        modelSelection.connectionOperationInProgress = true
        defer {
            modelSelection.connectionOperationInProgress = false
            requestModelFeatureVerification()
        }
        do {
            let activation: VyronModelConnectionActivation
            if let id {
                guard let profile = modelSelection.connectionProfiles.first(where: { $0.id == id }) else {
                    throw ModelProviderError.invalidSettings(VyronStatusText.connectionUnavailable)
                }
                let provider = try modelSelection.makeProvider(for: profile, apiKey: savedAPIKey(for: id))
                activation = VyronModelConnectionActivation(
                    id: id,
                    provider: provider,
                    model: profile.selectedModel,
                    automaticallySelect: false
                )
            } else {
                activation = modelSelection.builtinActivation
            }
            var saved = modelSelection.connectionState
            saved.activeConnectionID = id
            try modelSelection.persist(saved)
            await switchInferenceConnection(activation)
        } catch {
            modelSelection.connectionError = error.localizedDescription
        }
    }

    func deleteConnection(_ id: UUID) async {
        guard canManageModelSelection, !modelDownloads.isActive else {
            modelSelection.connectionError = modelConnectionBusyError.localizedDescription
            return
        }
        localAuthentication.invalidate(connectionID: id)
        modelSelection.connectionOperationInProgress = true
        defer { modelSelection.connectionOperationInProgress = false }
        do {
            let remaining = modelSelection.connectionProfiles.filter { $0.id != id }
            let wasActive = modelSelection.activeConnectionID == id
            let nextActive = wasActive ? nil : modelSelection.activeConnectionID
            var saved = modelSelection.connectionState
            saved.profiles = remaining
            saved.activeConnectionID = nextActive
            try modelSelection.persist(saved)
            do { try modelCredentialStore.removeKey(for: id) } catch {
                try? modelSelection.persist(modelSelection.connectionState)
                throw error
            }
            modelSelection.connectionProfiles = remaining
            // Record backup deletion before a model refresh can suspend or the app can quit.
            await localAuthentication.remove(connectionID: id)
            if wasActive {
                // The deletion was already persisted; commit the local state without a second save.
                await switchInferenceConnection(modelSelection.builtinActivation)
            }
            modelSelection.connectionStatus = VyronStatusText.connectionRemoved
        } catch { modelSelection.connectionError = error.localizedDescription }
    }

    func saveBuiltinModelSettings(_ requested: ModelSettings) throws {
        guard canManageModelSelection, !modelDownloads.isActive else { throw modelConnectionBusyError }
        try modelSelection.applyBuiltinSettings(requested)
        cancelModelFeatureVerification()
        modelSelection.connectionStatus = VyronStatusText.localSettingsSaved
        modelSelection.connectionError = nil
        requestModelFeatureVerification()
    }

    private var modelConnectionBusyError: ModelProviderError {
        .invalidSettings(VyronStatusText.connectionChangeBusy)
    }

    private func switchInferenceConnection(_ activation: VyronModelConnectionActivation) async {
        cancelModelFeatureVerification()
        modelSelection.activate(activation)
        errorMessage = nil
        statusMessage = VyronStatusText.usingConnection(
            modelSelection.activeConnectionName,
            modelSelection.inferenceLocationLabel
        )
        if modelSelection.isBuiltinConnection { await startEngine() } else { await refreshModels() }
    }

    func verifyModelResponse(provider: any ModelProvider, model: String) async throws {
        _ = try await provider.chat(
            model: model,
            messages: [ChatMessage(role: .user, content: "Reply with OK.")],
            systemPrompt: "This is a connection test. Give a very short text reply.",
            onToken: { _ in }
        )
        try Task.checkCancellation()
    }
}
