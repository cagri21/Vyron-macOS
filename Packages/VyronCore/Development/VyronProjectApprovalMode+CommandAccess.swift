import VyronDevelopment

extension VyronProjectApprovalMode {
    var commandAccess: VyronCommandAccess {
        self == .fullAccess ? .fullAccess : .restricted
    }
}
