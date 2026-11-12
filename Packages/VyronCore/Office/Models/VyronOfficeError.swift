import Foundation

public struct VyronOfficeError: Error, LocalizedError, Sendable, Equatable {
    public let message: String

    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}
