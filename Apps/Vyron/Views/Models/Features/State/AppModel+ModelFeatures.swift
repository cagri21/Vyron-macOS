import Foundation
import VyronCore
import VyronModelData
import VyronModelDomain

extension AppModel {
    var modelFeatureReport: VyronModelFeatureReport {
        let selected = featureSelectionModel
        return featureReport(connection: modelSelection.activeConnectionProfile, model: selected)
    }

    var modelThinkingSupport: VyronModelThinkingSupport {
        thinkingSupport(connection: modelSelection.activeConnectionProfile, modelName: featureSelectionModel.name)
    }

    func modelThinkingSupport(
        for profile: ModelConnectionProfile,
        discoveredModel: LocalModel? = nil
    ) -> VyronModelThinkingSupport {
        let normalized = (try? profile.validated()) ?? profile
        return thinkingSupport(
            connection: normalized,
            modelName: discoveredModel?.name ?? normalized.selectedModel
        )
    }

    func modelFeatureReport(
        for profile: ModelConnectionProfile,
        discoveredModel: LocalModel? = nil
    ) -> VyronModelFeatureReport {
        let normalized = (try? profile.validated()) ?? profile
        let local = discoveredModel ?? LocalModel(name: normalized.selectedModel, size: 0)
        return featureReport(connection: normalized, model: local)
    }

    func isComposerModeAvailable(_ mode: ComposerMode) -> Bool {
        switch mode {
        case .chat: return true
        case .agent: return modelFeatureReport[.agent].isEnabled
        case .plan:
            // Planning without a project uses the plain Chat transport and needs no tools.
            return workspaceState.workspaceURL == nil || modelFeatureReport[.plan].isEnabled
        }
    }

    func composerModeAvailabilityDescription(_ mode: ComposerMode) -> String? {
        guard !isComposerModeAvailable(mode) else { return nil }
        return VyronModelFeaturePresentation.reason(modelFeatureReport[mode == .agent ? .agent : .plan].reason)
    }

    func invalidateModelFeatureVerification(for connectionID: UUID) {
        modelFeatures.removeChecks(for: connectionID)
        if modelSelection.activeConnectionID == connectionID { cancelModelFeatureVerification() }
    }

    func cancelModelFeatureVerification() {
        modelFeatures.cancelVerification()
    }

    func recordModelThinkingSupport(
        _ support: VyronModelThinkingSupport,
        selection: VyronModelFeatureSelection
    ) {
        guard selection.revision == modelSelection.connectionRevision, !isShuttingDown else { return }
        modelFeatures.record(support, for: selection)
    }

    func recordModelToolVerification(
        _ result: VyronNativeToolVerification,
        selection: VyronModelFeatureSelection
    ) {
        guard selection.revision == modelSelection.connectionRevision, !isShuttingDown else { return }
        modelFeatures.record(result, for: selection)
    }

    func retainConnectionFeatureVerification(
        from selection: VyronModelFeatureSelection,
        for requestedProfile: ModelConnectionProfile? = nil
    ) {
        guard let profile = requestedProfile ?? selection.connection else { return }
        let current = modelFeatureSelection(for: profile)
        if let result = modelFeatures.toolChecks.last(where: { $0.selection == selection })?.result {
            recordModelToolVerification(result, selection: current)
        }
        if let support = modelFeatures.thinkingChecks.last(where: { $0.selection == selection })?.support {
            recordModelThinkingSupport(support, selection: current)
        }
    }

    func modelFeatureSelection(for profile: ModelConnectionProfile) -> VyronModelFeatureSelection {
        let normalized = (try? profile.validated()) ?? profile
        return VyronModelFeatureSelection(
            connection: normalized,
            modelName: normalized.selectedModel,
            revision: modelSelection.connectionRevision
        )
    }

    func checkModelTools(
        provider: any ModelProvider,
        selection: VyronModelFeatureSelection
    ) async throws -> VyronNativeToolVerification {
        let report = VyronModelFeaturePolicy.assess(
            VyronModelFeatureContext(
                connection: selection.connection,
                model: LocalModel(name: selection.modelName, size: 0)
            )
        )
        guard report[.agent].isEnabled else { return .unsupported }
        do {
            _ = try await provider.developmentModel(
                model: selection.modelName,
                automaticModelSelection: false,
                effort: .quick
            )
            try Task.checkCancellation()
            return .verified
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ModelProviderError where error == .unsupportedTools {
            return .unsupported
        } catch {
            try Task.checkCancellation()
            return .failed
        }
    }

    func verifyConnectionFeatures(
        provider: any ModelProvider,
        selection: VyronModelFeatureSelection
    ) async throws -> VyronNativeToolVerification {
        let verification = try await checkModelTools(provider: provider, selection: selection)
        recordModelToolVerification(verification, selection: selection)
        if let thinking = provider as? any VyronModelThinkingControlProviding {
            do {
                let support = try await thinking.thinkingControlSupport(
                    for: LocalModel(name: selection.modelName, size: 0)
                )
                try Task.checkCancellation()
                recordModelThinkingSupport(support, selection: selection)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                recordModelThinkingSupport(.unverified, selection: selection)
            }
        }
        return verification
    }

    func requestModelFeatureVerification() {
        cancelModelFeatureVerification()
        guard !isShuttingDown, modelSelection.isConnected, !foregroundRun.isGenerating,
            !modelSelection.connectionOperationInProgress, let provider = modelSelection.inferenceProvider
        else { return }
        let local = featureSelectionModel
        let selection = currentModelFeatureSelection
        guard !local.name.isEmpty else { return }
        let checkTools =
            modelFeatureReport[.agent].status == .unverified
            && !modelFeatures.toolChecks.contains(where: { $0.selection == selection })
        let thinking = provider as? any VyronModelThinkingControlProviding
        let checkThinking = thinking != nil && !modelFeatures.thinkingChecks.contains { $0.selection == selection }
        guard checkTools || checkThinking else { return }
        modelFeatures.startVerification { [weak self] in
            guard let self else { return }
            do {
                if checkTools {
                    let result = try await checkModelTools(provider: provider, selection: selection)
                    try Task.checkCancellation()
                    guard currentModelFeatureSelection == selection else { return }
                    recordModelToolVerification(result, selection: selection)
                }
                if checkThinking, let thinking {
                    let support = try await thinking.thinkingControlSupport(for: local)
                    try Task.checkCancellation()
                    guard currentModelFeatureSelection == selection else { return }
                    recordModelThinkingSupport(support, selection: selection)
                }
            } catch {
                // Cancellation and stale selections do not change the next model's availability.
                guard !Task.isCancelled, currentModelFeatureSelection == selection else { return }
                if checkTools, !modelFeatures.toolChecks.contains(where: { $0.selection == selection }) {
                    recordModelToolVerification(.failed, selection: selection)
                }
                if checkThinking { recordModelThinkingSupport(.unverified, selection: selection) }
            }
        }
    }

    func retryModelFeatureVerification() {
        let selection = currentModelFeatureSelection
        modelFeatures.removeChecks(for: selection)
        requestModelFeatureVerification()
    }

    func scheduledModelFeatureReport(_ selection: VyronScheduledModelSelection) -> VyronModelFeatureReport {
        let connection = selection.connectionID.flatMap { id in
            modelSelection.connectionProfiles.first { $0.id == id }
        }
        // A saved Auto request resolves its current coding model through the provider at execution time.
        // The saved manual selection can still be a Chat helper and must not block that routing.
        let name = selection.automaticallySelect && selection.connectionID == nil ? "" : selection.model
        return VyronModelFeaturePolicy.assess(
            VyronModelFeatureContext(
                connection: connection,
                model: LocalModel(name: name, size: 0)
            )
        )
    }

    private var currentModelFeatureSelection: VyronModelFeatureSelection {
        VyronModelFeatureSelection(
            connection: modelSelection.activeConnectionProfile,
            modelName: featureSelectionModel.name,
            revision: modelSelection.connectionRevision
        )
    }

    private var featureSelectionModel: LocalModel {
        if modelSelection.isBuiltinConnection, modelSelection.automaticModelSelection,
            let automatic = try? AgentModelRouter.selectCodingModel(
                from: modelSelection.models,
                selectedModel: modelSelection.selectedModel,
                automaticModelSelection: true,
                effort: composer.effort == .automatic ? .balanced : composer.effort
            ) {
            return automatic
        }
        return modelSelection.models.first { modelSelection.modelNamesMatch($0.name, modelSelection.selectedModel) }
            ?? LocalModel(name: modelSelection.selectedModel, size: 0)
    }

    private func featureReport(connection: ModelConnectionProfile?, model: LocalModel) -> VyronModelFeatureReport {
        let selection = VyronModelFeatureSelection(
            connection: connection,
            modelName: model.name,
            revision: modelSelection.connectionRevision
        )
        let verification = modelFeatures.toolChecks.last { $0.selection == selection }?.result ?? .unverified
        return VyronModelFeaturePolicy.assess(
            VyronModelFeatureContext(
                connection: connection,
                model: model,
                toolVerification: verification,
                thinkingSupport: thinkingSupport(connection: connection, modelName: model.name)
            )
        )
    }

    private func thinkingSupport(
        connection: ModelConnectionProfile?,
        modelName: String
    ) -> VyronModelThinkingSupport {
        if let connection, VyronDeepSeekRoute.matches(connection) {
            return VyronDeepSeekRoute.thinkingSupport(for: modelName)
        }
        if let connection, connection.kind != .ollama { return .unsupported }
        return modelFeatures.thinkingChecks.last { check in
            check.selection.revision == modelSelection.connectionRevision && check.selection.modelName == modelName
                && check.selection.connection?.id == connection?.id
                && check.selection.connection?.endpoint == connection?.endpoint
                && check.selection.connection?.kind == connection?.kind
        }?.support ?? .unverified
    }
}
