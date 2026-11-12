import Foundation
import VyronModelDomain

struct DevelopmentStepResponse: Decodable {
    let message: DevelopmentMessage?
    let done: Bool?
    let error: String?
    let doneReason: String?

}
