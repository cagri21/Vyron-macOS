import Combine
import Foundation

@MainActor
final class VyronBillingBrowserModel: ObservableObject {
    @Published private(set) var request: VyronBillingBrowserRequest?
    @Published private(set) var state = VyronBillingBrowserState(phase: .idle, host: nil)

    func open() {
        guard let url = VyronBillingDashboard.openAI else {
            state = VyronBillingBrowserState(phase: .failed, host: nil)
            return
        }
        request = VyronBillingBrowserRequest(id: UUID(), url: url)
        state = VyronBillingBrowserState(phase: .loading, host: url.host)
    }

    func loading(_ id: UUID) {
        guard request?.id == id, state.phase != .failed, state.phase != .browserSignInRequired else { return }
        state.phase = .loading
    }

    func committed(_ id: UUID, url: URL?) {
        guard request?.id == id, state.phase == .loading,
            VyronBillingNavigationPolicy.decision(for: url, isMainFrame: true) == .allow else { return }
        state.host = url?.host
    }

    func finished(_ id: UUID) {
        guard request?.id == id, state.phase == .loading else { return }
        state.phase = .ready
    }

    func failed(_ id: UUID) {
        guard request?.id == id, state.phase != .browserSignInRequired else { return }
        state.phase = .failed
    }

    func requiresBrowser(_ id: UUID) {
        guard request?.id == id else { return }
        state.phase = .browserSignInRequired
    }

    func close() {
        request = nil
        state = VyronBillingBrowserState(phase: .idle, host: nil)
    }
}
