import Foundation
import VyronModelDomain

struct VyronModelConnectionActivation {
    let id: UUID?
    let provider: (any ModelProvider)?
    let model: String
    let automaticallySelect: Bool
}
