import Foundation
import VyronModelDomain

struct VyronOllamaModelShowResponse: Decodable {
    let capabilities: [String]?
    let thinking: Thinking?
    let remote_model: String?
    let remote_host: String?
    let model_info: [String: DevelopmentJSONValue]?
    var maximumContextTokens: Int? {
        model_info?.compactMap { key, value -> Int? in
            guard key.hasSuffix(".context_length"), case .number(let number) = value,
                number.isFinite, number.rounded() == number, number > 0, number <= Double(Int32.max)
            else { return nil }
            return Int(number)
        }.min()
    }
}
