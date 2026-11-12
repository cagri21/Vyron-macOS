import Foundation
import VyronModelDomain

struct ControlPlanningRequest: Encodable {

    let model: String
    let messages: [Message]
    let think: VyronOllamaThinkingValue?
    let stream = false
    let options: Options
    let keep_alive = "5m"
    let format = ControlProposalSchema()

    init(model: String, messages: [Message], think: VyronOllamaThinkingValue?, options: Options = Options()) {
        self.model = model
        self.messages = messages
        self.think = think
        self.options = options
    }
}
