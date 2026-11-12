import Foundation
import VyronCore

extension AppModel {
    func downloadModel(_ requestedTag: String) {
        let tag = requestedTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard modelSelection.isBuiltinConnection else {
            errorMessage = VyronStatusText.selectLocalForDownload
            return
        }
        guard canManageModelSelection else {
            errorMessage = VyronStatusText.downloadBusy
            return
        }
        guard !modelDownloads.isActive else {
            errorMessage = VyronStatusText.pauseDownloadFirst
            return
        }
        guard modelSelection.isConnected else {
            errorMessage = VyronStatusText.startEngineForDownload
            return
        }
        do { try OllamaClient.validateModelName(tag) } catch { errorMessage = error.localizedDescription; return }

        errorMessage = nil
        statusMessage = VyronStatusText.downloadingModel(tag)
        modelDownloads.start(
            VyronModelTransfer(tag: tag, kind: .pull),
            operation: VyronModelTransferOperation(
                execute: { [client = modelSelection.builtinClient] progress in
                    try await client.pull(model: tag, onProgress: progress)
                    return tag
                },
                refreshModels: { [weak self] in await self?.refreshModels(quiet: true) },
                complete: { [weak self] result in
                    switch result {
                    case .success(let model): self?.statusMessage = VyronStatusText.modelReady(model)
                    case .failure(let error): self?.errorMessage = error.localizedDescription
                    }
                }
            )
        )
    }

    func importModelVariant(_ request: VyronModelImportRequest) {
        guard canManageModelSelection, !modelDownloads.isActive, modelSelection.isBuiltinConnection else {
            modelSelection.connectionError = VyronStatusText.importBusy
            return
        }
        if let tag = request.variant.ollamaTag {
            modelSelection.connectionError = nil
            modelSelection.connectionStatus = nil
            downloadModel(tag)
            return
        }
        let localName = request.name.trimmingCharacters(in: .whitespacesAndNewlines)
        do { try OllamaClient.validateModelName(localName) } catch {
            modelSelection.connectionError = error.localizedDescription
            return
        }
        guard !modelSelection.models.contains(where: { modelSelection.modelNamesMatch($0.name, localName) }) else {
            modelSelection.connectionError = VyronStatusText.modelNameExists(localName)
            return
        }

        let source = ModelSourceClient()
        modelSelection.connectionError = nil
        modelSelection.connectionStatus = VyronStatusText.downloadingVariant(request.variant.name)
        modelDownloads.start(
            VyronModelTransfer(tag: localName, kind: .ggufImport),
            operation: VyronModelTransferOperation(
                execute: { [weak self] progress in
                    guard let self else { throw CancellationError() }
                    if !modelSelection.isConnected { _ = try await runtime.startIfNeeded() }
                    try Task.checkCancellation()
                    return try await source.importModel(variant: request.variant, name: localName, onProgress: progress)
                },
                refreshModels: { [weak self] in await self?.refreshModels(quiet: true) },
                complete: { [weak self] result in
                    switch result {
                    case .success(let model):
                        let message = VyronStatusText.modelImported(model)
                        self?.modelSelection.connectionStatus = message
                        self?.statusMessage = message
                    case .failure(let error):
                        self?.modelSelection.connectionError = error.localizedDescription
                    }
                }
            )
        )
    }

    func cancelDownload() {
        switch modelDownloads.cancel() {
        case .pull:
            statusMessage = VyronStatusText.downloadPaused
        case .ggufImport:
            let message = VyronStatusText.importCanceled
            statusMessage = message
            modelSelection.connectionStatus = message
        case nil:
            break
        }
    }
}
