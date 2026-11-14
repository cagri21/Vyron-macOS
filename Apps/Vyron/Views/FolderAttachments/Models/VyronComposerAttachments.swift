import VyronCore

struct VyronComposerAttachments: Sendable {
    var images: [VyronImageAttachment] = []
    var folders: [VyronFolderAttachment] = []
    var pdfs: [VyronPDFAttachment] = []
    var files: [VyronFileAttachment] = []
    var applications: [VyronApplicationAttachment] = []

    init() {}
}
