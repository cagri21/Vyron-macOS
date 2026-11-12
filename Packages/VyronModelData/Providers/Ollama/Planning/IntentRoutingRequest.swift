import Foundation
import VyronModelDomain

struct IntentRoutingRequest: Encodable {
    let model: String
    let messages: [ControlPlanningRequest.Message]
    let think: VyronOllamaThinkingValue?
    let options: Options
    let stream = false
    let keep_alive = "5m"
    let format = AssistantRouteSchema()
}
