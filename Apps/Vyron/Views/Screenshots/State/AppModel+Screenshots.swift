import AppKit
import VyronCore

extension AppModel {
    var canAttachScreenshots: Bool {
        isConversationModeCompatible(composer.mode)
            && !isShuttingDown && !foregroundRun.isGenerating && !computerWork.isComputerWorkActive && !isRunningScheduledTask
            && !foregroundRun.isStoppingDevelopment && !composer.isEditingQueuedMessage && !composerAttachments.isImporting
            && composerAttachments.screenshotDraft.images.count < VyronImageAttachment.maximumCount
    }

    var screenshotAnalysisHint: String {
        let usesOllama = modelSelection.isBuiltinConnection || modelSelection.activeConnectionProfile?.kind == .ollama
        if let capabilities = modelSelection.models.first(where: {
            modelSelection.modelNamesMatch($0.name, modelSelection.selectedModel)
        })?.capabilities,
            !capabilities.isEmpty {
            if capabilities.contains("vision") { return VyronScreenshotText.analysisHint }
            return usesOllama ? VyronScreenshotText.localTextHint : VyronScreenshotText.visionRequired
        }
        if usesOllama { return VyronScreenshotText.localTextHint }
        return VyronScreenshotText.analysisHint
    }

    func openScreenshotPicker() {
        guard canAttachScreenshots else { return }
        composerAttachments.screenshotCaptureGeneration = composerAttachments.screenshotDraft.generation
        composerAttachments.showScreenshotPicker = true
    }

    func importScreenshotImages(_ urls: [URL]) {
        guard canAttachScreenshots, !urls.isEmpty else { return }
        guard urls.count + composerAttachments.screenshotDraft.images.count <= VyronImageAttachment.maximumCount else {
            errorMessage = VyronScreenshotText.attachmentLimit
            return
        }
        loadScreenshotImages {
            let loader = VyronScreenshotImageLoader()
            var images: [VyronImageAttachment] = []
            for url in urls { images.append(try await loader.load(url)) }
            return images
        }
    }

    func pasteScreenshotImage() {
        guard canAttachScreenshots else { return }
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else {
            errorMessage = VyronScreenshotText.clipboardEmpty
            return
        }
        attachCapturedScreenshot(data, name: VyronScreenshotText.pastedImage)
    }

    func attachCapturedScreenshot(_ data: Data, name: String) {
        guard canAttachScreenshots else { return }
        loadScreenshotImages {
            [try await VyronScreenshotImageLoader().load(data, name: name)]
        }
    }

    func completeScreenshotCapture(_ data: Data, name: String, generation: UUID?) {
        guard composerAttachments.showScreenshotPicker,
            generation == composerAttachments.screenshotDraft.generation
        else { return }
        attachCapturedScreenshot(data, name: name)
    }

    func removeScreenshot(_ id: UUID) {
        composerAttachments.screenshotDraft.images.removeAll { $0.id == id }
    }

    func loadScreenshotImages(
        _ load: @escaping @Sendable () async throws -> [VyronImageAttachment]
    ) {
        let generation = composerAttachments.screenshotDraft.generation
        composerAttachments.screenshotDraft.isLoading = true
        errorMessage = nil
        composerAttachments.screenshotImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if composerAttachments.screenshotDraft.generation == generation {
                    composerAttachments.screenshotDraft.isLoading = false
                    composerAttachments.screenshotImportTask = nil
                }
            }
            do {
                let images = try await load()
                try Task.checkCancellation()
                guard composerAttachments.screenshotDraft.generation == generation, !isShuttingDown,
                    isConversationModeCompatible(composer.mode)
                else { return }
                let combined = composerAttachments.screenshotDraft.images + images
                guard combined.count <= VyronImageAttachment.maximumCount,
                    combined.reduce(0, { $0 + $1.data.count }) <= VyronImageAttachment.maximumRequestDataBytes
                else { throw VyronScreenshotImportError.tooLarge }
                composerAttachments.screenshotDraft.images = combined
                statusMessage = VyronScreenshotText.readyToAnalyze
            } catch is CancellationError {
                return
            } catch {
                guard composerAttachments.screenshotDraft.generation == generation, !isShuttingDown else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}
