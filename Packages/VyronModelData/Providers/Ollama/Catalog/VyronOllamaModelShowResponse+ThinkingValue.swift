extension VyronOllamaModelShowResponse {
    enum ThinkingValue: Decodable, Equatable {
        case boolean(Bool)
        case level(String)

        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let boolean = try? value.decode(Bool.self) {
                self = .boolean(boolean)
            } else {
                self = .level(try value.decode(String.self))
            }
        }
    }
}
