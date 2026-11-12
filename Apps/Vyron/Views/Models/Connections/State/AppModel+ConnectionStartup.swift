import Foundation

extension AppModel {
    /// The window must exist before an updated app may need access to an older Keychain item.
    func prepareActiveModelConnection(readKey: @Sendable (UUID) async throws -> String) async {
        await modelSelection.prepareActiveConnection(readKey: readKey, canApply: { !isShuttingDown })
    }
}
