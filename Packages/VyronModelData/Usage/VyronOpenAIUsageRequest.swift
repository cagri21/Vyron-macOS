import Foundation
import VyronModelDomain

struct VyronOpenAIUsageRequest {
    let id = UUID()
    let startedAt = Date()
    let model: String
}
