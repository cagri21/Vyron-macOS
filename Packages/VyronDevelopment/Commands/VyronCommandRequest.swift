import Foundation

public struct VyronCommandRequest: Sendable {
    public let command: String
    public let timeout: TimeInterval
    public let access: VyronCommandAccess
    public let approved: Bool

    public init(
        command: String,
        timeout: TimeInterval = 120,
        access: VyronCommandAccess = .restricted,
        approved: Bool = false
    ) {
        self.command = command
        self.timeout = timeout
        self.access = access
        self.approved = approved
    }
}
