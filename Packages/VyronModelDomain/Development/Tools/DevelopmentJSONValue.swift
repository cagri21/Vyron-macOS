import Foundation

public enum DevelopmentJSONValue: Codable, Sendable, Equatable {
    case string(String), number(Double), bool(Bool), object([String: DevelopmentJSONValue]), array(
        [DevelopmentJSONValue]
    ), null

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() {
            self = .null
        } else if let boolean = try? value.decode(Bool.self) {
            self = .bool(boolean)
        } else if let number = try? value.decode(Double.self) {
            self = .number(number)
        } else if let text = try? value.decode(String.self) {
            self = .string(text)
        } else if let object = try? value.decode([String: DevelopmentJSONValue].self) {
            self = .object(object)
        } else {
            self = .array(try value.decode([DevelopmentJSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let text): try value.encode(text)
        case .number(let number): try value.encode(number)
        case .bool(let boolean): try value.encode(boolean)
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .null: try value.encodeNil()
        }
    }
}
