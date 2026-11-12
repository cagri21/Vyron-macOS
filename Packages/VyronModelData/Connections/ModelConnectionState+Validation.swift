import Foundation
import VyronLocalization
import VyronModelDomain

extension ModelConnectionState {
    public func validated() throws -> ModelConnectionState {
        guard profiles.count <= VyronModelConnectionLimits.maximumProfiles,
            Set(profiles.map(\.id)).count == profiles.count
        else {
            throw ModelProviderError.invalidSettings(
                VyronModelDataText.duplicateOrTooManyConnections
            )
        }
        if let activeConnectionID, !profiles.contains(where: { $0.id == activeConnectionID }) {
            throw ModelProviderError.invalidSettings(VyronModelDataText.activeConnectionMissing)
        }
        return try ModelConnectionState(
            profiles: profiles.map { try $0.validated() },
            activeConnectionID: activeConnectionID,
            builtinSettings: builtinSettings.validated()
        )
    }
}
