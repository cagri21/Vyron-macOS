import Foundation

public struct VyronConversationCompactionRequest: Sendable {
    public let messages: [ChatMessage]
    public let throughMessageID: UUID
    public let wasTruncated: Bool

    public init(messages: [ChatMessage], throughMessageID: UUID, wasTruncated: Bool) {
        self.messages = messages
        self.throughMessageID = throughMessageID
        self.wasTruncated = wasTruncated
    }
}
