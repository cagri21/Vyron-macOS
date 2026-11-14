import Foundation
import VyronModelDomain

enum VyronOllamaAgentApplicationCatalog {
    private static let displayNameSuffixes = ["desktop", "player", "app"]
    private static let minimumAliasLength = 4

    static func rankedApplications(
        _ applications: [AgentApplication], goal: String, snapshotApplicationID: String?
    ) -> [AgentApplication] {
        let lowerGoal = goal.lowercased()
        let compactGoal = compactName(goal)
        let browserGoal = ["http", "browser", "website", "web page"].contains { lowerGoal.contains($0) }
        var scores: [String: Int] = [:]
        let eligibleApplications = applications.filter { application in
            guard ControlProposal.validApplicationID(application.id), !application.name.isEmpty,
                scores[application.id] == nil
            else { return false }
            scores[application.id] = nameScore(application, lowerGoal: lowerGoal, compactGoal: compactGoal)
                + (application.id == snapshotApplicationID ? 20 : 0)
                + (browserGoal && ControlProposal.browserApplicationIDs.contains(application.id) ? 10 : 0)
                + (application.isRunning ? 2 : 0)
            return true
        }
        let ranked = eligibleApplications.sorted { first, second in
            let firstScore = scores[first.id, default: 0]
            let secondScore = scores[second.id, default: 0]
            return firstScore == secondScore ? first.id < second.id : firstScore > secondScore
        }
        return Array(ranked.prefix(VyronOllamaPlanningLimits.maximumCandidateApplications))
    }

    private static func nameScore(_ application: AgentApplication, lowerGoal: String, compactGoal: String) -> Int {
        let name = application.name.lowercased()
        let compactDisplayName = compactName(name)
        if lowerGoal.contains(name) || lowerGoal.contains(application.id.lowercased())
            || (!compactDisplayName.isEmpty && compactGoal.contains(compactDisplayName)) {
            return 100
        }
        let words = name.split(whereSeparator: \.isWhitespace)
        guard words.count > 1, let suffix = words.last, displayNameSuffixes.contains(String(suffix)) else { return 0 }
        let alias = compactName(words.dropLast().joined(separator: " "))
        return alias.count >= minimumAliasLength && compactGoal.contains(alias) ? 60 : 0
    }

    private static func compactName(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
