extension VyronOllamaModelPayload {
    struct Details: Decodable {
        let parameter_size: String?
        let quantization_level: String?
    }
}
