import Foundation
import VyronModelDomain

struct VyronMacWorkContext {
    let goal: String
    let projectRoot: URL?
    let allowsActions: Bool
    let attachedApplications: [VyronApplicationAttachment]

    init(
        goal: String,
        projectRoot: URL?,
        allowsActions: Bool,
        attachedApplications: [VyronApplicationAttachment] = []
    ) {
        self.goal = goal
        self.projectRoot = projectRoot
        self.allowsActions = allowsActions
        self.attachedApplications = attachedApplications
    }
}
