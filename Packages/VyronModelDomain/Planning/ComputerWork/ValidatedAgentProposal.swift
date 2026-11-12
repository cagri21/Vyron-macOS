import Foundation
import VyronLocalization

package func validatedAgentProposal(
    _ proposal: ControlProposal,
    applications: [AgentApplication],
    snapshot: AgentSnapshot?
) throws -> ControlProposal {
    let validated = try proposal.validated()
    guard let application = applications.first(where: { $0.id == validated.applicationID }) else {
        throw AgentPlanningError.invalidDecision(VyronModelDomainText.agentApplicationUnavailable)
    }
    switch validated.kind {
    case .launch:
        guard !application.isRunning else {
            throw AgentPlanningError.invalidDecision(
                VyronModelDomainText.agentApplicationAlreadyRunning
            )
        }
    case .inspect, .activate, .wait:
        guard application.isRunning else {
            throw AgentPlanningError.invalidDecision(
                VyronModelDomainText.agentLaunchBeforeInspecting
            )
        }
    case .openURL:
        guard application.isRunning else {
            throw AgentPlanningError.invalidDecision(VyronModelDomainText.agentLaunchBrowser)
        }
    case .click, .typeText, .pressKey, .complete:
        guard application.isRunning, let snapshot, snapshot.applicationID == application.id, snapshot.isFresh else {
            throw AgentPlanningError.invalidDecision(
                VyronModelDomainText.agentInspectAgain
            )
        }
        _ = try validated.validated(expectedApplicationID: application.id, availableElementIDs: snapshot.elementIDs)
    }
    return validated
}
