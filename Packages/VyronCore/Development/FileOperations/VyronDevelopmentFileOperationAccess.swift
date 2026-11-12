public struct VyronDevelopmentFileOperationAccess: Sendable {
    let approve: @Sendable (CommandApproval) async -> Bool

    public init(approve: @escaping @Sendable (CommandApproval) async -> Bool) {
        self.approve = approve
    }
}
