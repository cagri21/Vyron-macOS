import Foundation

public struct VyronLocalCredentialBackupResult: Sendable, Equatable {
    public let status: VyronLocalAuthStatus
    public let restorations: [VyronLocalCredentialRestoration]

    public init(status: VyronLocalAuthStatus, restorations: [VyronLocalCredentialRestoration] = []) {
        self.status = status
        self.restorations = restorations
    }
}
