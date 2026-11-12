import VyronCore

enum VyronProjectApprovalPresentation {
    static func title(_ mode: VyronProjectApprovalMode) -> String {
        switch mode {
        case .askForApproval: VyronWorkspaceText.askForApproval
        case .approveForMe: VyronWorkspaceText.approveForMe
        case .fullAccess: VyronWorkspaceText.fullAccess
        }
    }

    static func description(_ mode: VyronProjectApprovalMode) -> String {
        switch mode {
        case .askForApproval: VyronWorkspaceText.askForApprovalDescription
        case .approveForMe: VyronWorkspaceText.approveForMeDescription
        case .fullAccess: VyronWorkspaceText.fullAccessDescription
        }
    }

    static func symbol(_ mode: VyronProjectApprovalMode) -> String {
        switch mode {
        case .askForApproval: VyronSymbols.hand
        case .approveForMe: VyronSymbols.eye
        case .fullAccess: VyronSymbols.access
        }
    }
}
