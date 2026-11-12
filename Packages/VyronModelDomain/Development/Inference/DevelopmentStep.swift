import Foundation

public struct DevelopmentStep: Sendable {
    public let message: DevelopmentMessage
    public init(message: DevelopmentMessage) { self.message = message }
}
