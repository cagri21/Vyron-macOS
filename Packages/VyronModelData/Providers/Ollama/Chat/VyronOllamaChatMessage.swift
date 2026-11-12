import Foundation
import VyronModelDomain

struct VyronOllamaChatMessage: Codable {
    let role: String
    let content: String
    var images: [String]? = nil
}
