import Foundation

extension ResponseActivity {
    public struct Entry: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public let date: Date
        public let content: VyronActivityContent

        public var kind: Kind { content.kind }
        public var title: String { content.title }
        public var detail: String? { content.detail }
        public var category: VyronActivityCategory? { content.category }

        public init(id: UUID, date: Date, content: VyronActivityContent) {
            self.id = id
            self.date = date
            self.content = content
        }

        // Retain the flat keys used by existing conversation history.
        public init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: VyronActivityEntryCodingKey.self)
            id = try values.decode(UUID.self, forKey: .id)
            date = try values.decode(Date.self, forKey: .date)
            content = try VyronActivityContent(
                kind: values.decode(Kind.self, forKey: .kind),
                title: values.decode(String.self, forKey: .title),
                detail: values.decodeIfPresent(String.self, forKey: .detail),
                category: values.decodeIfPresent(VyronActivityCategory.self, forKey: .category)
            )
        }

        public func encode(to encoder: any Encoder) throws {
            var values = encoder.container(keyedBy: VyronActivityEntryCodingKey.self)
            try values.encode(id, forKey: .id)
            try values.encode(date, forKey: .date)
            try values.encode(kind, forKey: .kind)
            try values.encode(title, forKey: .title)
            try values.encodeIfPresent(detail, forKey: .detail)
            try values.encodeIfPresent(category, forKey: .category)
        }
    }
}
