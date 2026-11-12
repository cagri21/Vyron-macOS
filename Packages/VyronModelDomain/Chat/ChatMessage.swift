import Foundation

public struct ChatMessage: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    /// The stored role retains its original value, including roles outside the chat transcript.
    public let role: String
    public var content: String
    public var activity: ResponseActivity?
    public var suggestedQuestions: [String]?
    public var images: [VyronImageAttachment]?
    /// The task text stays in `content` so inference and task continuation can use it directly.
    package var developmentTaskFilename: String?
    /// Screenshots produced by a Work response, retained as artifacts rather than future model inputs.
    public var capturedImages: [VyronImageAttachment]?
    /// Owning assistant response for a clarification child; absent in legacy conversation history.
    public var parentResponseID: UUID?

    public var conversationRole: VyronChatMessageRole? {
        VyronChatMessageRole(rawValue: role)
    }

    public init(
        id: UUID = UUID(),
        role: VyronChatMessageRole,
        content: String,
        activity: ResponseActivity? = nil
    ) {
        self.init(id: id, role: role.rawValue, content: content, activity: activity)
    }

    public init(role: VyronChatMessageRole, content: String, images: [VyronImageAttachment]) {
        self.init(role: role.rawValue, content: content, images: images)
    }

    public init(
        id: UUID = UUID(),
        role: String,
        content: String,
        activity: ResponseActivity? = nil,
        suggestedQuestions: [String]? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.activity = activity
        self.suggestedQuestions = suggestedQuestions
    }

    public init(role: String, content: String, images: [VyronImageAttachment]) {
        self.init(role: role, content: content)
        self.images = images.isEmpty ? nil : images
    }
}
