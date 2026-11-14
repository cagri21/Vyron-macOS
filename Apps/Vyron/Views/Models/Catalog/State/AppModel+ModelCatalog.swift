import Foundation
import VyronModelDomain
import VyronRuntime

extension AppModel {
    var canManageModelSelection: Bool {
        !isShuttingDown && !modelSelection.isStarting && !modelSelection.connectionOperationInProgress
            && !modelDownloads.isChangingPrecision
            && !foregroundRun.isGenerating && !foregroundRun.isStoppingDevelopment && scheduledTasks.activeTaskID == nil
            && !computerWork.isPlanningControls && !computerWork.isComputerWorkActive
    }

    func startEngine() async {
        guard !isShuttingDown, !Task.isCancelled, !modelDownloads.isChangingPrecision else { return }
        guard modelSelection.isBuiltinConnection else { await refreshModels(); return }
        guard !modelSelection.isStarting else { return }
        modelSelection.isStarting = true
        defer { modelSelection.isStarting = false }
        do {
            _ = try await runtime.startIfNeeded()
            guard !isShuttingDown, !Task.isCancelled else { return }
            await refreshModels()
        } catch is CancellationError {
            return
        } catch {
            guard !isShuttingDown, !Task.isCancelled else { return }
            modelSelection.isConnected = false
            statusMessage = VyronStatusText.startOllama
            if LocalRuntimeManager.executableURL != nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    func refreshModels(quiet: Bool = false, duringPrecisionChange: Bool = false) async {
        guard !modelDownloads.isChangingPrecision || duringPrecisionChange else { return }
        guard !modelSelection.isRefreshing else { return }
        if modelSelection.inferenceProvider != nil { modelDownloads.refreshStorageCapacity() }
        let revision = modelSelection.connectionRevision
        let result = await modelSelection.refreshCatalog()
        guard revision == modelSelection.connectionRevision, !isShuttingDown, !Task.isCancelled else { return }
        switch result {
        case .unchanged:
            break
        case .loaded:
            if modelSelection.isBuiltinConnection {
                modelDownloads.reconcileInstalledModels { tag in
                    modelSelection.models.contains { ModelCatalog.sameInstalledName($0.name, tag) }
                }
            }
            if !quiet { statusMessage = modelSelection.models.isEmpty ? VyronStatusText.downloadToBegin : nil }
            if !duringPrecisionChange { requestModelFeatureVerification() }
            modelDownloads.refreshStorageCapacity()
        case .failed(let failure):
            if !quiet {
                statusMessage = VyronStatusText.connectionNotResponding(modelSelection.activeConnectionName)
                if !modelSelection.isBuiltinConnection { modelSelection.connectionError = failure.detail }
            }
        }
    }

    func startRefreshingModels() {
        modelSelection.startPeriodicRefresh { [weak self] in
            guard let self, !isShuttingDown else { return }
            if !foregroundRun.isGenerating && !modelSelection.connectionOperationInProgress && !computerWork.isPlanningControls
                && !modelDownloads.isActive && !foregroundRun.isStoppingDevelopment && scheduledTasks.activeTaskID == nil {
                await refreshModels(quiet: true)
            }
        }
    }

    func useLocalModel(_ name: String, forChat: Bool = false) {
        guard canManageModelSelection else {
            errorMessage = VyronStatusText.modelChangeBusy
            return
        }
        guard !forChat || isConversationModeCompatible(.chat) else {
            errorMessage = VyronWorkspaceText.modeLocked
            return
        }
        do {
            let installed = try modelSelection.selectInstalledModel(name)
            errorMessage = nil
            if forChat { composer.mode = .chat }
            statusMessage =
                forChat
                ? VyronStatusText.usingManualChatModel(installed.name)
                : VyronStatusText.usingManualModel(installed.name)
            requestModelFeatureVerification()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func useAutomaticModels() {
        guard canManageModelSelection, modelSelection.isBuiltinConnection else { return }
        do {
            try modelSelection.useAutomaticSelection(forChat: composer.mode == .chat)
            errorMessage = nil
            statusMessage = VyronStatusText.automaticModelHint
            requestModelFeatureVerification()
        } catch {
            statusMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }
}
