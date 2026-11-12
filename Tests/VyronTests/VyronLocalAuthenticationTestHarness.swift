import Foundation
@testable import Vyron
import VyronCore

@MainActor
struct VyronLocalAuthenticationTestHarness {
    let backup: VyronLocalAuthenticationTestBackup
    let actions: VyronLocalAuthenticationTestActions
    let model: VyronLocalAuthenticationModel

    init() {
        let backup = VyronLocalAuthenticationTestBackup()
        self.backup = backup
        actions = VyronLocalAuthenticationTestActions()
        model = VyronLocalAuthenticationModel(backup: backup)
    }

    func cleanUp() async {
        let pending = model.shutdown()
        await backup.cancelAll()
        await pending?.value
    }

    func waitForSynchronizations(_ count: Int) async -> Bool {
        await waitUntil { await backup.synchronizations.count == count }
    }

    func waitForRemovals(_ count: Int) async -> Bool {
        await waitUntil { await backup.removals.count == count }
    }

    func waitForStatus(_ status: VyronLocalAuthStatus) async -> Bool {
        await waitUntil { model.status == status }
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while clock.now < deadline {
            if await condition() { return true }
            do { try await Task.sleep(for: .milliseconds(5)) } catch { return false }
        }
        return await condition()
    }
}
