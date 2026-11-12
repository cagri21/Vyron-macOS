import Foundation
import VyronModelDomain

struct VyronOllamaChatOptions: Encodable {
    let num_ctx: Int
    let num_predict: Int
    let temperature: Double
    let top_p: Double?
}
