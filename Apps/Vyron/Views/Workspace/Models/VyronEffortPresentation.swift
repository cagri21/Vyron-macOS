import VyronCore

enum VyronEffortPresentation {
    static let manualEfforts: [AgentEffort] = [.quick, .balanced, .deep, .extraHigh, .maximum, .ultra]
    static let maximumPosition = Double(manualEfforts.count - 1)

    static func title(_ effort: AgentEffort) -> String {
        switch effort {
        case .automatic: VyronWorkspaceText.automaticEffort
        case .quick: VyronWorkspaceText.lowEffort
        case .balanced: VyronWorkspaceText.mediumEffort
        case .deep: VyronWorkspaceText.highEffort
        case .extraHigh: VyronWorkspaceText.extraHighEffort
        case .maximum: VyronWorkspaceText.maxEffort
        case .ultra: VyronWorkspaceText.ultraEffort
        }
    }

    static func description(_ effort: AgentEffort) -> String {
        switch effort {
        case .automatic: VyronWorkspaceText.automaticEffortDescription
        case .quick: VyronWorkspaceText.lowEffortDescription
        case .balanced: VyronWorkspaceText.mediumEffortDescription
        case .deep: VyronWorkspaceText.highEffortDescription
        case .extraHigh: VyronWorkspaceText.extraHighEffortDescription
        case .maximum: VyronWorkspaceText.maxEffortDescription
        case .ultra: VyronWorkspaceText.ultraEffortDescription
        }
    }

    static func position(for effort: AgentEffort) -> Double {
        switch effort {
        case .quick: 0
        case .automatic, .balanced: 1
        case .deep: 2
        case .extraHigh: 3
        case .maximum: 4
        case .ultra: 5
        }
    }

    static func manualEffort(at position: Double) -> AgentEffort {
        guard position.isFinite else { return .balanced }
        let index = Int(min(maximumPosition, max(0, position)).rounded())
        return manualEfforts[index]
    }

    static func steppedEffort(from effort: AgentEffort, by offset: Int) -> AgentEffort {
        guard offset != 0 else { return effort }
        return manualEffort(at: position(for: effort) + Double(offset))
    }
}
