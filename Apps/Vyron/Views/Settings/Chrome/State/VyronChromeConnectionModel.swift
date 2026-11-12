import Combine
import Foundation
import VyronAutomation

@MainActor
final class VyronChromeConnectionModel: ObservableObject {
    @Published var extensionID = ""
    @Published private(set) var sessionCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var status: String?
    private let client: VyronChromeBridgeClient
    private var generation: UUID?

    init(client: VyronChromeBridgeClient) {
        self.client = client
    }

    func install() {
        do {
            try VyronChromeHostRegistration.register(
                extensionID: extensionID.trimmingCharacters(in: .whitespacesAndNewlines),
                appURL: Bundle.main.bundleURL,
                home: FileManager.default.homeDirectoryForCurrentUser
            )
            error = nil
            status = VyronChromeText.installed
        } catch {
            self.error = error.localizedDescription
            status = nil
        }
    }

    func refresh() async {
        let id = UUID()
        generation = id
        isLoading = true
        defer {
            if generation == id { isLoading = false }
        }
        do {
            let sessions = try await client.sessions()
            guard !Task.isCancelled, generation == id else { return }
            sessionCount = sessions.count
            error = nil
        } catch {
            guard !Task.isCancelled, generation == id else { return }
            self.error = error.localizedDescription
        }
    }

    func cancel() {
        generation = nil
        isLoading = false
    }
}
