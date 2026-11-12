import Foundation
import VyronModelDomain

struct VyronOllamaModelShowRequest: Encodable {
    let model: String
    let verbose = false
}
