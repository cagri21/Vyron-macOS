import AppKit
import VyronCore

extension AppModel {
    var canAttachFiles: Bool {
        canStartFileAttachmentImport && (canAttachScreenshots || canAttachPDFs
            || composerAttachments.files.count < VyronFileAttachmentLimits.maximumCount)
    }

    func chooseFileAttachments() {
        guard canAttachFiles else { return }
        let panel = NSOpenPanel()
        panel.title = VyronFolderAttachmentText.fileChoose
        panel.allowedContentTypes = VyronComposerFileLoader.fileTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        let generation = composerAttachments.folderAttachmentDraft.generation
        guard panel.runModal() == .OK, composerAttachments.folderAttachmentDraft.generation == generation
        else { return }
        importFileAttachments(panel.urls)
    }

    func importFileAttachments(_ urls: [URL]) {
        guard canAttachFiles, !urls.isEmpty else { return }
        loadComposerAttachments { try await VyronComposerFileLoader().load(urls) }
    }

    func removeFileAttachment(_ id: UUID) {
        composerAttachments.files.removeAll { $0.id == id }
    }
}
