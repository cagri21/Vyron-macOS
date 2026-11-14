import Foundation

extension AppModel {
    func importPDFAttachments(_ urls: [URL]) {
        guard canAttachPDFs, !urls.isEmpty else { return }
        guard urls.count + composerAttachments.pdfs.count <= VyronPDFAttachmentLimits.maximumCount else {
            errorMessage = VyronPDFAttachmentError.tooMany.localizedDescription
            return
        }
        loadComposerAttachments {
            let loader = VyronPDFAttachmentLoader()
            var result = VyronComposerAttachments()
            for url in urls { result.pdfs.append(try await loader.load(url)) }
            return result
        }
    }

    func removePDFAttachment(_ id: UUID) {
        composerAttachments.pdfs.removeAll { $0.id == id }
    }
}
