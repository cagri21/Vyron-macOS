import Foundation
import VyronModelDomain

struct AgentPlanningRequest: Encodable {
    let model: String
    let messages: [ControlPlanningRequest.Message]
    let stream = false
    let options: Options
    let think: VyronOllamaThinkingValue?
    let keep_alive = "5m"
    let format = ControlProposalSchema()
}
