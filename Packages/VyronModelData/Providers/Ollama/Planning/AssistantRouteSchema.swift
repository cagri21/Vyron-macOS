import Foundation
import VyronModelDomain

struct AssistantRouteSchema: Encodable {
    let type = "object"
    let additionalProperties = false
    let required = ["mode", "goal", "clarification", "effort"]
    let properties: [String: Property] = [
        "mode": Property(type: ["string"], enum: ["conversation", "computerTask", "clarify"], maxLength: nil),
        "goal": Property(type: ["string", "null"], enum: nil, maxLength: VyronTaskPromptLimits.maximumCharacters),
        "clarification": Property(
            type: ["string", "null"],
            enum: nil,
            maxLength: VyronIntentRoutingLimits.maximumClarificationCharacters
        ),
        "effort": Property(type: ["string"], enum: AgentEffort.allCases.map(\.rawValue), maxLength: nil)
    ]
}
