import Foundation
import VyronCore
@testable import Vyron

@MainActor
final class VyronWebConversationHarness {
    let base: VyronFeatureTestHarness
    let access = VyronWebConversationAccess()
    let provider = VyronWebConversationProvider()

    var model: AppModel { base.model }

    init() throws {
        base = try VyronFeatureTestHarness()
        base.select(base.profile(), provider: provider, capabilities: ["tools"])
        model.webAccess = access
        model.computerWork.automaticRequestRouting = true
    }

    func finishReply() async throws {
        try await base.waitUntil { !self.model.foregroundRun.isGenerating }
    }

    func cleanUp() { base.cleanUp() }
}
