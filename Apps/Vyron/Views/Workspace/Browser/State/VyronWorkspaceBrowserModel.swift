import Combine
import Foundation
import VyronCore

@MainActor
final class VyronWorkspaceBrowserModel: ObservableObject {
    @Published private(set) var request: VyronWorkspaceBrowserRequest?
    @Published private(set) var address = ""
    @Published private(set) var displayTitle = ""
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var renderedReader: VyronWorkspaceBrowserReader?
    private(set) var generationID = UUID()
    private var phase = VyronWorkspaceBrowserPhase.stopped

    init(url: URL, renderedReader: VyronWorkspaceBrowserReader? = nil) {
        displayTitle = VyronBrowserText.untitled
        if let renderedReader {
            self.renderedReader = renderedReader
            address = url.absoluteString
            displayTitle = url.host ?? displayTitle
            beginPageNavigation()
        } else {
            navigate(to: url)
        }
    }

    var url: URL? {
        guard let value = URL(string: address), VyronWorkspaceBrowserPolicy.allows(value) else { return nil }
        return value
    }

    func readRenderedPage() async throws -> VyronWebPage {
        guard let renderedReader, let url else { throw VyronWebError.unavailable }
        let id = generationID
        do {
            let page = try await renderedReader.read(url: url)
            try Task.checkCancellation()
            guard generationID == id else { throw CancellationError() }
            finished(id, snapshot: VyronWorkspaceBrowserSnapshot(
                url: page.source.url, title: page.source.title, canGoBack: false, canGoForward: false
            ))
            return page
        } catch is CancellationError {
            cancelled(id)
            throw CancellationError()
        } catch {
            failed(id, message: error.localizedDescription)
            throw error
        }
    }

    func navigate(to url: URL) {
        guard VyronWorkspaceBrowserPolicy.allows(url) else {
            errorMessage = VyronBrowserText.invalidAddress
            return
        }
        renderedReader?.cancel()
        renderedReader = nil
        address = url.absoluteString
        displayTitle = url.host ?? VyronBrowserText.untitled
        issue(.navigate(VyronWorkspaceBrowserLocation(url: url)))
    }

    func goBack() {
        guard canGoBack else { return }
        issue(.back)
    }

    func goForward() {
        guard canGoForward else { return }
        issue(.forward)
    }

    func reload() {
        guard let url else { return }
        if renderedReader != nil { navigate(to: url) } else { issue(.reload) }
    }

    func stop() {
        renderedReader?.cancel()
        issue(.stop)
    }

    /// Navigation initiated inside the current page has no new representable command.
    @discardableResult
    func beginPageNavigation() -> UUID {
        generationID = UUID()
        phase = .loading
        isLoading = true
        errorMessage = nil
        return generationID
    }

    func started(_ id: UUID) {
        guard generationID == id, phase == .loading else { return }
        isLoading = true
    }

    func updated(_ id: UUID, snapshot: VyronWorkspaceBrowserSnapshot) {
        guard generationID == id, phase == .loading || phase == .ready else { return }
        if let url = snapshot.url, VyronWorkspaceBrowserPolicy.allows(url) {
            address = url.absoluteString
        }
        if let title = snapshot.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            displayTitle = title
        }
        canGoBack = snapshot.canGoBack
        canGoForward = snapshot.canGoForward
    }

    func finished(_ id: UUID, snapshot: VyronWorkspaceBrowserSnapshot) {
        guard generationID == id, phase == .loading else { return }
        updated(id, snapshot: snapshot)
        phase = .ready
        isLoading = false
        errorMessage = nil
    }

    func failed(_ id: UUID, message: String) {
        guard generationID == id, phase != .stopped, phase != .failed else { return }
        phase = .failed
        isLoading = false
        errorMessage = message
    }

    func cancelled(_ id: UUID) {
        guard generationID == id, phase == .loading else { return }
        phase = .stopped
        isLoading = false
        errorMessage = nil
    }

    private func issue(_ command: VyronWorkspaceBrowserCommand) {
        let id = UUID()
        generationID = id
        let stops = command == .stop
        phase = stops ? .stopped : .loading
        isLoading = !stops
        errorMessage = nil
        request = VyronWorkspaceBrowserRequest(id: id, command: command)
    }
}
