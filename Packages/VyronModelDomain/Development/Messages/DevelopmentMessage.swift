import Foundation

public struct DevelopmentMessage: Codable, Sendable, Equatable {
    public let role: String
    public let content: String
    public let toolCalls: [DevelopmentToolCall]?
    public let toolName: String?
    public let toolCallID: String?
    public let continuation: VyronModelContinuation?
    public let images: [VyronImageAttachment]?
    public let imageObservation: VyronDevelopmentImageObservation?

    // Retain the established five-argument public initializer and serialized tool association contract.
    // New continuation state uses a separate message-and-context initializer below.
    public init(
        role: String,
        content: String = "",
        toolCalls: [DevelopmentToolCall]? = nil,
        toolName: String? = nil,
        toolCallID: String? = nil
    ) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolName = toolName
        self.toolCallID = toolCallID
        continuation = nil
        images = nil
        imageObservation = nil
    }

    public init(role: String, content: String, images: [VyronImageAttachment]) {
        self.init(message: DevelopmentMessage(role: role, content: content), images: images)
    }

    public init(message: DevelopmentMessage, images: [VyronImageAttachment]?) {
        role = message.role
        content = message.content
        toolCalls = message.toolCalls
        toolName = message.toolName
        toolCallID = message.toolCallID
        continuation = message.continuation
        self.images = images?.isEmpty == false ? images : nil
        imageObservation = message.imageObservation
    }

    public init(message: DevelopmentMessage, continuation: VyronModelContinuation) {
        role = message.role
        content = message.content
        toolCalls = message.toolCalls
        toolName = message.toolName
        toolCallID = message.toolCallID
        self.continuation = continuation
        images = message.images
        imageObservation = message.imageObservation
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        role = try values.decode(String.self, forKey: .role)
        content = try values.decodeIfPresent(String.self, forKey: .content) ?? ""
        toolCalls = try values.decodeIfPresent([DevelopmentToolCall].self, forKey: .toolCalls)
        toolName = try values.decodeIfPresent(String.self, forKey: .toolName)
        toolCallID = try values.decodeIfPresent(String.self, forKey: .toolCallID)
        continuation = try values.decodeIfPresent(VyronModelContinuation.self, forKey: .continuation)
        images = try values.decodeIfPresent([VyronImageAttachment].self, forKey: .images)
        imageObservation = try values.decodeIfPresent(VyronDevelopmentImageObservation.self, forKey: .imageObservation)
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(role, forKey: .role)
        try values.encode(content, forKey: .content)
        try values.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try values.encodeIfPresent(toolName, forKey: .toolName)
        try values.encodeIfPresent(toolCallID, forKey: .toolCallID)
        try values.encodeIfPresent(continuation, forKey: .continuation)
        try values.encodeIfPresent(images, forKey: .images)
        try values.encodeIfPresent(imageObservation, forKey: .imageObservation)
    }
}
