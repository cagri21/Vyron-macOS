import Foundation
import VyronModelDomain

struct ChatEvent: Decodable {
    let message: Message?
    let done: Bool?
    let error: String?
}
