import Foundation
import VyronDevelopment

struct VyronDevelopmentReadEvidence: Encodable {
    let path: String
    let contentHash: String
    let coverage: VyronDevelopmentFileReadCoverage
    let incomplete: Bool
}
