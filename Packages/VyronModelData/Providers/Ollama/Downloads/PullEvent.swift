import Foundation
import VyronModelDomain

struct PullEvent: Decodable {
    let status: String?
    let completed: Int64?
    let total: Int64?
    let error: String?
}
