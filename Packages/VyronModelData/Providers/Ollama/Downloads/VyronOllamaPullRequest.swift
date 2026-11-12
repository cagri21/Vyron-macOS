import Foundation
import VyronModelDomain

struct VyronOllamaPullRequest: Encodable { let model: String; let stream = true }
