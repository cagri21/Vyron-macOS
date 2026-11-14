import VyronCore

struct VyronConversationSubmissionReferences {
    let folders: String
    let pdfs: [VyronPDFAttachment]
    let files: [VyronFileAttachment]
    let applications: [VyronApplicationAttachment]

    var context: String {
        [
            VyronPDFAttachmentContext.make(pdfs),
            VyronFileAttachmentContext.make(files),
            folders,
            VyronApplicationAttachmentContext.make(applications) ?? ""
        ]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
