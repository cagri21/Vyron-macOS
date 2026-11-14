import Observation
import VyronAutomation

@MainActor @Observable
final class VyronPermissionsViewModel {
    private let access: VyronPermissionsSystemAccess
    private var statuses: [VyronMacPrivacyPane: VyronPermissionStatus] = [:]
    private(set) var pendingRequest: VyronMacPrivacyPane?
    private(set) var isRequesting = false
    var showsSettingsError = false

    init(access: VyronPermissionsSystemAccess) {
        self.access = access
    }

    func status(for pane: VyronMacPrivacyPane) -> VyronPermissionStatus {
        statuses[pane] ?? .unavailable
    }

    func refresh() {
        for pane in VyronMacPrivacyPane.allCases {
            statuses[pane] = access.status(pane)
        }
    }

    func openSettings(for pane: VyronMacPrivacyPane) {
        showsSettingsError = !access.openSettings(pane)
    }

    func queueRequest(for pane: VyronMacPrivacyPane) {
        guard pendingRequest == nil, status(for: pane) == .notRequested else { return }
        pendingRequest = pane
    }

    func requestPendingAccess() async {
        guard !isRequesting, let pendingRequest else { return }
        defer {
            isRequesting = false
            self.pendingRequest = nil
        }
        guard !Task.isCancelled else { return }
        isRequesting = true
        await access.request(pendingRequest)
        refresh()
    }
}
