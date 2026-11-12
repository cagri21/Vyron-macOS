import Foundation
import VyronModelDomain

struct ControlPlanningResponse: Decodable {
    let message: Message?
    let done: Bool?
    let error: String?
}
