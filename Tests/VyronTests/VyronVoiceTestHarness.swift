import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronVoiceTestHarness {
    let speech = VyronSpeechTestService()
    let conversation = VyronVoiceTestConversation()
    let defaults: UserDefaults
    let model: VyronVoiceModel
    private let suiteName = "VyronVoiceTests-\(UUID())"

    init(silenceDelay: Duration = .milliseconds(40)) throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        model = VyronVoiceModel(service: speech, defaults: defaults, silenceDelay: silenceDelay)
        model.conversation = conversation
    }

    func cleanUp() {
        model.end()
        for index in speech.sessions.indices { speech.grantPermission(index) }
        defaults.removePersistentDomain(forName: suiteName)
    }

    func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        _ = try XCTUnwrap(condition() ? true : nil, "Voice state did not settle")
    }
}
