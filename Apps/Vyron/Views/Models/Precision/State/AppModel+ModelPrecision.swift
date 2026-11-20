import Foundation
import VyronModelData
import VyronModelDomain

extension AppModel {
    var canChangeLocalModelPrecision: Bool {
        canManageModelSelection && modelSelection.isBuiltinConnection && modelSelection.isConnected
            && !modelSelection.isRefreshing && !modelDownloads.isActive
            && foregroundRun.backgroundResponseIdentities.isEmpty
            && !newSideChatSessions.values.contains { $0.isGenerating }
    }

    func precisionOptions(for installed: LocalModel) async throws -> VyronModelPrecisionOptions {
        guard canChangeLocalModelPrecision else { throw precisionReplacementUnavailable }
        let revision = modelSelection.connectionRevision
        let original = try await modelSelection.builtinClient.installedModelIdentity(named: installed.name)
        let local = ModelSourceClient.installedPrecisionVariants(for: original.model, among: modelSelection.models)
        let published: [ModelSourceVariant]
        do {
            published = try await ModelSourceClient().discoverPrecisionVariants(for: original.model)
        } catch {
            try Task.checkCancellation()
            guard !local.isEmpty else { throw error }
            published = []
        }
        try Task.checkCancellation()
        guard modelSelection.isBuiltinConnection, modelSelection.connectionRevision == revision else {
            throw precisionReplacementUnavailable
        }
        let variants = local + published.filter { variant in
            !local.contains { VyronModelPrecisionTag.matches($0.ollamaTag, variant.ollamaTag) }
        }
        let alternatives = variants.filter { variant in
            guard let tag = variant.ollamaTag, let precision = variant.quantization else { return false }
            return !VyronModelPrecisionTag.matches(original.name, tag)
                && original.model.quantization?.caseInsensitiveCompare(precision) != .orderedSame
        }
        return VyronModelPrecisionOptions(
            original: original, variants: alternatives,
            connectionRevision: revision, installedVariantIDs: Set(local.map(\.id))
        )
    }

    func changeModelPrecision(_ change: VyronModelPrecisionChange) -> Bool {
        guard canChangeLocalModelPrecision, modelSelection.connectionRevision == change.connectionRevision,
            let tag = change.replacement.ollamaTag, let precision = change.replacement.quantization,
            !VyronModelPrecisionTag.matches(change.original.name, tag),
            change.original.model.quantization?.caseInsensitiveCompare(precision) != .orderedSame
        else {
            modelSelection.connectionError = VyronAppText.settingsPrecisionReplacementUnavailable
            return false
        }
        let transfer = VyronModelTransfer(tag: tag, kind: .precisionReplacement(change))
        guard modelDownloads.start(
            transfer,
            operation: VyronModelTransferOperation(
                execute: { [weak self] progress in
                    guard let self else { throw CancellationError() }
                    return try await performPrecisionChange(change, transfer: transfer, onProgress: progress)
                },
                refreshModels: { [weak self] in await self?.refreshModels(quiet: true, duringPrecisionChange: true) },
                complete: { [weak self] result in self?.finishPrecisionChange(change, result: result) }
            )
        ) else { return false }
        cancelModelFeatureVerification()
        modelSelection.connectionError = nil
        modelSelection.connectionStatus = nil
        return true
    }

    private func performPrecisionChange(
        _ change: VyronModelPrecisionChange,
        transfer: VyronModelTransfer,
        onProgress: @escaping @Sendable (ModelPullProgress) -> Void
    ) async throws -> String {
        let client = modelSelection.builtinClient
        try checkPrecisionChangeContext(change)
        let original = try await client.installedModelIdentity(named: change.original.name)
        guard original.name == change.original.name, original.digest == change.original.digest else {
            throw precisionReplacementUnavailable
        }
        let replacement: VyronOllamaInstalledModelIdentity
        if let installed = try await client.installedModelIdentityIfPresent(named: transfer.tag) {
            replacement = installed
        } else {
            guard change.mayDownloadReplacement else { throw precisionReplacementUnavailable }
            try checkPrecisionChangeContext(change)
            try await client.pull(model: transfer.tag, onProgress: onProgress)
            replacement = try await client.installedModelIdentity(named: transfer.tag)
        }
        guard let precision = change.replacement.quantization,
            replacement.model.quantization?.caseInsensitiveCompare(precision) == .orderedSame,
            !VyronModelPrecisionTag.matches(original.name, replacement.name), original.digest != replacement.digest
        else { throw precisionReplacementUnavailable }

        try checkPrecisionChangeContext(change)
        try await verifyModelResponse(provider: client, model: replacement.name)
        try checkPrecisionChangeContext(change)
        await refreshModels(quiet: true, duringPrecisionChange: true)
        let ready = try await client.installedModelIdentity(named: replacement.name)
        try checkPrecisionChangeContext(change)
        guard ready.name == replacement.name, ready.digest == replacement.digest,
            modelSelection.models.contains(where: { $0.name == ready.name })
        else {
            throw precisionReplacementUnavailable
        }

        // Commit the local selection on the main actor before allowing the delete request.
        try modelDownloads.beginPrecisionRemoval(for: transfer) {
            _ = try modelSelection.selectInstalledModel(replacement.name, readKey: savedAPIKey(for:))
        }
        requestModelFeatureVerification()
        do {
            try await client.deleteInstalledModel(original, keeping: replacement)
        } catch {
            await refreshModels(quiet: true, duringPrecisionChange: true)
            throw VyronModelPrecisionRemovalFailure(
                replacement: replacement.name, original: original.name, detail: error.localizedDescription
            )
        }
        return replacement.name
    }

    private func checkPrecisionChangeContext(_ change: VyronModelPrecisionChange) throws {
        try Task.checkCancellation()
        guard !isShuttingDown, modelSelection.isBuiltinConnection,
            modelSelection.connectionRevision == change.connectionRevision
        else { throw precisionReplacementUnavailable }
    }

    private func finishPrecisionChange(_ change: VyronModelPrecisionChange, result: Result<String, any Error>) {
        switch result {
        case .success(let tag):
            let message = VyronAppText.settingsPrecisionReplacementSucceeded(tag, change.original.name)
            modelSelection.connectionError = nil
            modelSelection.connectionStatus = message
            statusMessage = message
        case .failure(let error as VyronModelPrecisionRemovalFailure):
            modelSelection.connectionError = error.localizedDescription
        case .failure(let error):
            modelSelection.connectionError = VyronAppText.settingsPrecisionSwitchFailed(
                change.original.name, error.localizedDescription
            )
        }
    }

    private var precisionReplacementUnavailable: ModelProviderError {
        .invalidSettings(VyronAppText.settingsPrecisionReplacementUnavailable)
    }
}
