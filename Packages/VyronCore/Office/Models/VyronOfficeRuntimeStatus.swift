import Foundation

public struct VyronOfficeRuntimeStatus: Sendable, Equatable, Encodable {
    public let isAvailable: Bool
    public let message: String
    public let pythonExecutable: String?

    public init(isAvailable: Bool, message: String, pythonExecutable: String?) {
        self.isAvailable = isAvailable
        self.message = message
        self.pythonExecutable = pythonExecutable
    }
}
