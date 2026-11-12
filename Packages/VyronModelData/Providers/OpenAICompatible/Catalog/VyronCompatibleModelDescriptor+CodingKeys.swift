import VyronModelDomain

extension VyronCompatibleModelDescriptor {
    enum CodingKeys: String, CodingKey {
        case id, capabilities, quantization
        case parameterSize = "parameter_size"
    }
}
