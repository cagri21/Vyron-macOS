import Foundation

public struct LocalModel: Identifiable, Codable, Sendable, Equatable {
    public var id: String { name }
    public let name: String
    public let size: Int64
    public let parameterSize: String?
    public let quantization: String?
    public let capabilities: [String]?

    public init(
        name: String,
        size: Int64,
        parameterSize: String? = nil,
        quantization: String? = nil,
        capabilities: [String]? = nil
    ) {
        self.name = name
        self.size = size
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.capabilities = capabilities
    }
}
