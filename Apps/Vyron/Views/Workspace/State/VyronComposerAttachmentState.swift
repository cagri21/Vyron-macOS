import Combine
import Foundation

@MainActor
final class VyronComposerAttachmentState: ObservableObject {
    @Published var attachedFiles: [AttachedFile] = []
    @Published var screenshotDraft = VyronScreenshotDraft()
    @Published var folderAttachmentDraft = VyronFolderAttachmentDraft()
    @Published var pdfs: [VyronPDFAttachment] = []
    @Published var files: [VyronFileAttachment] = []
    @Published var showScreenshotPicker = false
    @Published var pendingAttachments: Set<String> = []

    var folderAttachmentImportTask: Task<Void, Never>?
    var screenshotCaptureGeneration: UUID?
    var screenshotImportTask: Task<Void, Never>?
    var generation = UUID()

    var isImporting: Bool { screenshotDraft.isLoading || folderAttachmentDraft.isLoading }
    var hasDrafts: Bool {
        !screenshotDraft.images.isEmpty || !folderAttachmentDraft.folders.isEmpty || !pdfs.isEmpty || !files.isEmpty
    }

    func resetDrafts() {
        resetScreenshotDraft()
        resetFolderAttachmentDraft()
    }

    func resetPending() {
        resetDrafts()
        generation = UUID()
        pendingAttachments = []
    }

    private func resetScreenshotDraft() {
        screenshotImportTask?.cancel()
        screenshotImportTask = nil
        screenshotDraft = VyronScreenshotDraft()
        screenshotCaptureGeneration = nil
        showScreenshotPicker = false
    }

    private func resetFolderAttachmentDraft() {
        folderAttachmentImportTask?.cancel()
        folderAttachmentImportTask = nil
        folderAttachmentDraft = VyronFolderAttachmentDraft()
        pdfs = []
        files = []
    }
}
