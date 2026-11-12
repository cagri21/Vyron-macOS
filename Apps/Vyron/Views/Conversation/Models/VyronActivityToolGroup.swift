import Foundation
import VyronCore

struct VyronActivityToolGroup: Identifiable, Equatable, Sendable {
    let id: UUID
    let entries: [ResponseActivity.Entry]

    var summary: String {
        var categories = Set<VyronActivityCategory>()
        let phrases = entries.compactMap { entry -> String? in
            let category = entry.category == .files ? .read : entry.category ?? .general
            guard categories.insert(category).inserted else { return nil }
            switch category {
            case .files, .read: return VyronTrackingText.readFiles
            case .search: return VyronTrackingText.searchedFiles
            case .edit: return VyronTrackingText.editedFiles
            case .command: return VyronTrackingText.ranCommands
            case .integration: return VyronTrackingText.usedIntegrations
            case .question: return VyronTrackingText.askedQuestions
            case .agents: return VyronTrackingText.parallelStarted
            case .general: return VyronAppText.activityTools
            }
        }
        let summary = phrases.joined(separator: ", ")
        guard let first = summary.first else { return VyronAppText.activityTools }
        return first.uppercased() + summary.dropFirst()
    }
}
