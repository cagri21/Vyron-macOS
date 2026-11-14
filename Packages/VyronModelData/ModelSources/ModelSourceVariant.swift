import Foundation

/// A published or locally installed model variant with its available precision metadata.
public struct ModelSourceVariant: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let downloadURL: URL?
    public let ollamaTag: String?
    public let quantization: String?
    public let parameterSize: String?
    public let sizeBytes: Int64?

    public init(
        id: String,
        name: String,
        downloadURL: URL? = nil,
        ollamaTag: String? = nil,
        quantization: String? = nil,
        parameterSize: String? = nil,
        sizeBytes: Int64? = nil
    ) {
        self.id = id
        self.name = name
        self.downloadURL = downloadURL
        self.ollamaTag = ollamaTag
        self.quantization = quantization
        self.parameterSize = parameterSize
        self.sizeBytes = sizeBytes
    }
}
