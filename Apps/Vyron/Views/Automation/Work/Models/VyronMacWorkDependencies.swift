import Foundation

@MainActor
struct VyronMacWorkDependencies {
    let controller: any VyronMacWorkControlling
    let validateCurrent: @MainActor () throws -> Void
    let review: @MainActor (MCPActionReview) async -> Bool
    let onTargetAction: @MainActor (VyronComputerActionFeedback) -> Void

    init(
        controller: any VyronMacWorkControlling,
        validateCurrent: @escaping @MainActor () throws -> Void,
        review: @escaping @MainActor (MCPActionReview) async -> Bool,
        onTargetAction: @escaping @MainActor (VyronComputerActionFeedback) -> Void = { _ in }
    ) {
        self.controller = controller
        self.validateCurrent = validateCurrent
        self.review = review
        self.onTargetAction = onTargetAction
    }
}
