struct VyronConversationSubmissionReferences {
    let folders: String
    let pdfs: [VyronPDFAttachment]
    let files: [VyronFileAttachment]

    var context: String {
        [VyronPDFAttachmentContext.make(pdfs), VyronFileAttachmentContext.make(files), folders]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
