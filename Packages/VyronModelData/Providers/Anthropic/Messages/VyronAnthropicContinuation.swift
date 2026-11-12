import Foundation
import VyronModelDomain

struct VyronAnthropicContinuation: Codable {
    let prefixDigest: Data
    let content: [DevelopmentJSONValue]
}
