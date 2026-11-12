import Foundation
import VyronModelDomain

struct ControlProposalSchema: Encodable {

    let type = "object"
    let additionalProperties = false
    let required = ["kind", "applicationID", "elementID", "text", "url", "key", "seconds", "explanation"]
    let properties: [String: Property] = [
        "kind": Property(["string"], values: ControlProposal.Kind.allCases.map(\.rawValue)),
        "applicationID": Property(["string"], maxLength: VyronControlProposalLimits.maximumApplicationIDUTF8Bytes),
        "elementID": Property(
            ["integer", "null"],
            minimum: VyronControlProposalLimits.elementIDs.lowerBound,
            maximum: VyronControlProposalLimits.elementIDs.upperBound - 1
        ),
        "text": Property(["string", "null"], maxLength: VyronControlProposalLimits.maximumTypedTextCharacters),
        "url": Property(["string", "null"], maxLength: VyronControlProposalLimits.maximumURLUTF8Bytes),
        "key": Property(["string", "null"], maxLength: 10),
        "seconds": Property(
            ["integer", "null"],
            minimum: VyronControlProposalLimits.waitSeconds.lowerBound,
            maximum: VyronControlProposalLimits.waitSeconds.upperBound
        ),
        "explanation": Property(["string"], maxLength: 500)
    ]
}
