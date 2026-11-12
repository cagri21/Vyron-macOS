import Foundation

public struct VyronLocalSkill: Identifiable, Sendable, Equatable {
    public let metadata: VyronSkillMetadata
    public let root: VyronSkillRoot
    public let fileURL: URL
    public let preview: VyronSkillPreview

    public var id: String { fileURL.path }
    public var name: String { metadata.name }
    public var description: String { metadata.description }
    public var source: VyronSkillSource { root.source }
    public var scope: VyronSkillScope { root.scope }
    public var content: String { preview.content }
    public var isContentTruncated: Bool { preview.isTruncated }

    public init(metadata: VyronSkillMetadata, root: VyronSkillRoot, fileURL: URL, preview: VyronSkillPreview) {
        self.metadata = metadata
        self.root = root
        self.fileURL = fileURL
        self.preview = preview
    }
}
