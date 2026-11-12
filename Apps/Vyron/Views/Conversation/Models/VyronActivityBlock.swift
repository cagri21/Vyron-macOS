import Foundation

enum VyronActivityBlock: Identifiable, Equatable, Sendable {
    case explanation(VyronActivityExplanation)
    case tools(VyronActivityToolGroup)

    var id: UUID {
        switch self {
        case .explanation(let explanation): explanation.id
        case .tools(let group): group.id
        }
    }
}
