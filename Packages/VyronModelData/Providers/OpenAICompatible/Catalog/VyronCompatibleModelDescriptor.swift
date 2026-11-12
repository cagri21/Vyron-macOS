import VyronModelDomain

/// Provider model-discovery fields form an external JSON boundary, rather than an internal constructor contract.
struct VyronCompatibleModelDescriptor: Decodable {
    let id: String
    let capabilities: [String]?
    let quantization: String?
    let parameterSize: String?
}
