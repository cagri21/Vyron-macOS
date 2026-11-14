import AppKit
import VyronCore

extension AppModel {
    nonisolated static let maximumFolderAttachments = 4
    nonisolated static let maximumApplicationAttachments = 4

    var canAttachFolders: Bool {
        canStartFileAttachmentImport
            && composerAttachments.folderAttachmentDraft.folders.count < Self.maximumFolderAttachments
    }

    var canAttachPDFs: Bool {
        canStartFileAttachmentImport && composerAttachments.pdfs.count < VyronPDFAttachmentLimits.maximumCount
    }

    var canStartFileAttachmentImport: Bool {
        isConversationModeCompatible(composer.mode)
            && !isShuttingDown && !foregroundRun.isGenerating && !computerWork.isComputerWorkActive && !isRunningScheduledTask
            && !foregroundRun.isStoppingDevelopment && !composer.isEditingQueuedMessage && !composerAttachments.isImporting
    }

    var canAcceptComposerDrop: Bool { canAttachFolders || canAttachFiles }

    func chooseFolderAttachment() {
        guard canAttachFolders else { return }
        let panel = NSOpenPanel()
        panel.title = VyronFolderAttachmentText.chooseFolder
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        let generation = composerAttachments.folderAttachmentDraft.generation
        guard panel.runModal() == .OK,
            composerAttachments.folderAttachmentDraft.generation == generation
        else { return }
        importFolderAttachments(panel.urls)
    }

    func importFolderAttachments(_ urls: [URL]) {
        guard canAttachFolders, !urls.isEmpty else { return }
        let attachedCount = composerAttachments.folderAttachmentDraft.folders.count
        guard urls.count + attachedCount <= Self.maximumFolderAttachments else {
            errorMessage = VyronFolderAttachmentText.tooMany
            return
        }
        loadComposerAttachments {
            let loader = VyronFolderAttachmentLoader()
            var result = VyronComposerAttachments()
            for url in urls { result.folders.append(try await loader.load(url)) }
            return result
        }
    }

    func acceptComposerDrop(_ providers: [NSItemProvider]) -> Bool {
        guard canAcceptComposerDrop, VyronComposerDropLoader.accepts(providers) else { return false }
        let loader = VyronComposerDropLoader(providers: providers)
        loadComposerAttachments { try await loader.load() }
        return true
    }

    func removeFolderAttachment(_ id: UUID) {
        composerAttachments.folderAttachmentDraft.folders.removeAll { $0.id == id }
    }

    func removeApplicationAttachment(_ id: UUID) {
        composerAttachments.applications.removeAll { $0.id == id }
    }

    func loadComposerAttachments(_ load: @escaping @Sendable () async throws -> VyronComposerAttachments) {
        guard canAcceptComposerDrop else { return }
        let generation = composerAttachments.folderAttachmentDraft.generation
        composerAttachments.folderAttachmentDraft.isLoading = true
        errorMessage = nil
        composerAttachments.folderAttachmentImportTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if composerAttachments.folderAttachmentDraft.generation == generation {
                    composerAttachments.folderAttachmentDraft.isLoading = false
                    composerAttachments.folderAttachmentImportTask = nil
                }
            }
            do {
                let result = try await load()
                try Task.checkCancellation()
                guard composerAttachments.folderAttachmentDraft.generation == generation, !isShuttingDown,
                    isConversationModeCompatible(composer.mode)
                else { return }
                let folders = composerAttachments.folderAttachmentDraft.folders + result.folders
                let images = composerAttachments.screenshotDraft.images + result.images
                let pdfs = composerAttachments.pdfs + result.pdfs
                let files = composerAttachments.files + result.files
                let applications = composerAttachments.applications + result.applications
                guard folders.count <= Self.maximumFolderAttachments else {
                    throw VyronFolderAttachmentDraftError.tooMany
                }
                guard images.count <= VyronImageAttachment.maximumCount,
                    images.reduce(0, { $0 + $1.data.count }) <= VyronImageAttachment.maximumRequestDataBytes
                else { throw VyronScreenshotImportError.tooLarge }
                guard pdfs.count <= VyronPDFAttachmentLimits.maximumCount
                else { throw VyronPDFAttachmentError.tooMany }
                guard files.count <= VyronFileAttachmentLimits.maximumCount
                else { throw VyronComposerFileImportError.tooMany }
                guard applications.count <= Self.maximumApplicationAttachments
                else { throw VyronApplicationAttachmentError.tooMany }
                guard Self.folderAttachmentContext(folders).utf8.count + VyronPDFAttachmentContext.make(pdfs).utf8.count
                    + VyronFileAttachmentContext.make(files).utf8.count
                    + VyronConversationRequestContext.systemPrompt.utf8.count
                    + VyronConversationLimits.folderImportOverheadBytes
                    < VyronScreenshotLimits.maximumConversationBudget
                else {
                    if !files.isEmpty { throw VyronComposerFileImportError.contextTooLarge }
                    if !pdfs.isEmpty { throw VyronPDFAttachmentError.contextTooLarge }
                    throw VyronFolderAttachmentDraftError.contextTooLarge
                }
                composerAttachments.folderAttachmentDraft.folders = folders
                composerAttachments.screenshotDraft.images = images
                composerAttachments.pdfs = pdfs
                composerAttachments.files = files
                composerAttachments.applications = applications
                if !result.files.isEmpty {
                    statusMessage = VyronFolderAttachmentText.fileReady
                } else if !result.pdfs.isEmpty {
                    statusMessage = VyronFolderAttachmentText.pdfReady
                } else if !result.applications.isEmpty {
                    statusMessage = VyronFolderAttachmentText.applicationReady
                } else {
                    statusMessage = result.folders.isEmpty ? VyronScreenshotText.readyToAnalyze : VyronFolderAttachmentText.ready
                }
            } catch is CancellationError {
                return
            } catch {
                guard composerAttachments.folderAttachmentDraft.generation == generation, !isShuttingDown
                else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    static func folderAttachmentContext(_ folders: [VyronFolderAttachment]) -> String {
        guard !folders.isEmpty else { return "" }
        return "<attached-folders>\n"
            + folders.map(\.context).joined(separator: "\n\n") + "\n</attached-folders>"
    }

    static func folderAttachmentReferenceContext(in messages: [ChatMessage], context: [String: String]) -> String? {
        for message in messages.reversed() where message.conversationRole == .user {
            guard let snapshot = context[message.id.uuidString],
                let start = snapshot.range(of: "<attached-folders>"),
                let end = snapshot.range(of: "</attached-folders>", range: start.upperBound..<snapshot.endIndex)
            else { continue }
            return String(snapshot[start.lowerBound..<end.upperBound])
        }
        return nil
    }
}
