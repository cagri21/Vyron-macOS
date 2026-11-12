import VyronCore

extension VyronProjectApprovalPresentation {
    static func reviewTitle(_ action: VyronDevelopmentApprovalAction) -> String {
        switch action {
        case .command: VyronGeneralText.reviewCommand
        case .createFolder: VyronFolderText.reviewTitle
        case .moveConversation: VyronSidebarText.moveTo
        case .moveProjectItem: VyronProjectItemText.moveReviewTitle
        case .renameProjectItem: VyronProjectItemText.renameReviewTitle
        case .trashProjectItem: VyronProjectItemText.trashReviewTitle
        }
    }

    static func confirmationTitle(_ action: VyronDevelopmentApprovalAction) -> String {
        switch action {
        case .command: VyronGeneralText.runCommand
        case .createFolder: VyronFolderText.allow
        case .moveConversation, .moveProjectItem: VyronProjectItemText.moveAllow
        case .renameProjectItem: VyronProjectItemText.renameAllow
        case .trashProjectItem: VyronProjectItemText.trashAllow
        }
    }

    static func reviewDetails(
        _ approval: CommandApproval, workspacePath: String, conversationTitle: String? = nil
    ) -> String {
        switch approval.action {
        case .command:
            VyronGeneralText.commandReviewDetails(
                approval.command,
                approval.reviewSource == .approvalSetting ? VyronWorkspaceText.approvalReviewReason : approval.reason,
                workspacePath
            )
        case .createFolder: VyronFolderText.reviewDetails(approval.command)
        case .moveConversation:
            [
                conversationTitle.map { VyronHandoffText.conversation + "\n" + $0 },
                VyronHandoffText.sourceFolder + "\n" + approval.command
            ].compactMap { $0 }.joined(separator: "\n\n")
        case .moveProjectItem: VyronProjectItemText.moveReviewDetails(approval.command)
        case .renameProjectItem: VyronProjectItemText.renameReviewDetails(approval.command)
        case .trashProjectItem: VyronProjectItemText.trashReviewDetails(approval.command)
        }
    }
}
