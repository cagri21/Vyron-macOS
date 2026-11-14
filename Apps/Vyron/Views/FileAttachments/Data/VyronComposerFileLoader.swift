import Foundation
import UniformTypeIdentifiers
import VyronCore

actor VyronComposerFileLoader {
    static var fileTypes: [UTType] {
        [.image, .pdf, .applicationBundle] + VyronAudioAttachmentLoader.acceptedTypes
            + VyronDocumentAttachmentLoader.contentTypes
    }

    private let folders = VyronFolderAttachmentLoader()
    private let images = VyronScreenshotImageLoader()
    private let pdfs = VyronPDFAttachmentLoader()
    private let audio = VyronAudioAttachmentLoader()
    private let documents = VyronDocumentAttachmentLoader()

    func load(_ urls: [URL]) async throws -> VyronComposerAttachments {
        var result = VyronComposerAttachments()
        for url in urls {
            try await append(url, to: &result)
        }
        return result
    }

    func append(_ url: URL, to result: inout VyronComposerAttachments) async throws {
        try Task.checkCancellation()
        guard url.isFileURL else { throw VyronFolderAttachmentError.invalidFolder }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        let filename = url.lastPathComponent
        let suffix = url.pathExtension.lowercased()
        if suffix == "app", values.isDirectory == true, values.isSymbolicLink != true {
            guard result.applications.count < AppModel.maximumApplicationAttachments
            else { throw VyronApplicationAttachmentError.tooMany }
            result.applications.append(VyronApplicationAttachment(name: filename, path: url.standardizedFileURL.path))
        } else if values.isDirectory == true || values.isSymbolicLink == true {
            guard result.folders.count < AppModel.maximumFolderAttachments
            else { throw VyronFolderAttachmentDraftError.tooMany }
            result.folders.append(try await folders.load(url))
        } else if suffix == "pdf" {
            guard result.pdfs.count < VyronPDFAttachmentLimits.maximumCount
            else { throw VyronPDFAttachmentError.tooMany }
            result.pdfs.append(try await pdfs.load(url))
        } else if VyronAudioAttachmentLoader.supports(filename: filename) {
            guard result.files.count < VyronFileAttachmentLimits.maximumCount
            else { throw VyronComposerFileImportError.tooMany }
            result.files.append(try await audio.load(url))
        } else if VyronImageAttachment.isImageFilenameExtension(suffix) {
            guard result.images.count < VyronImageAttachment.maximumCount
            else { throw VyronScreenshotImportError.tooLarge }
            result.images.append(try await images.load(url))
        } else if VyronDocumentAttachmentLoader.supports(filename: filename) {
            guard result.files.count < VyronFileAttachmentLimits.maximumCount
            else { throw VyronComposerFileImportError.tooMany }
            result.files.append(try await documents.load(url))
        } else {
            throw VyronComposerFileImportError.unsupported(filename)
        }
    }

    func appendPDF(_ data: Data, name: String, to result: inout VyronComposerAttachments) async throws {
        guard result.pdfs.count < VyronPDFAttachmentLimits.maximumCount else { throw VyronPDFAttachmentError.tooMany }
        result.pdfs.append(try await pdfs.load(data, name: name))
    }

    func appendAudio(_ data: Data, name: String, to result: inout VyronComposerAttachments) async throws {
        guard result.files.count < VyronFileAttachmentLimits.maximumCount
        else { throw VyronComposerFileImportError.tooMany }
        result.files.append(try await audio.load(data, name: name))
    }

    func appendDocument(_ data: Data, name: String, to result: inout VyronComposerAttachments) async throws {
        guard result.files.count < VyronFileAttachmentLimits.maximumCount
        else { throw VyronComposerFileImportError.tooMany }
        result.files.append(try await documents.load(data, name: name))
    }
}
