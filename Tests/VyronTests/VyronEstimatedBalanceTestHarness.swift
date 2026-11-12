import Foundation
import VyronCore
@testable import Vyron

@MainActor
final class VyronEstimatedBalanceTestHarness {
    let fixture = VyronBalanceTestHarness()
    let balances: VyronConnectionBalancesModel
    let profile: ModelConnectionProfile

    init(store: VyronEstimatedBalanceStore? = nil) {
        balances = VyronConnectionBalancesModel(dependencies: fixture.model.dependencies, estimateStore: store)
        profile = ModelConnectionProfile(
            name: "OpenAI", kind: .openAICompatible, endpoint: "https://api.openai.com/v1",
            selectedModel: "gpt-6.1-sol"
        )
        balances.configure(profiles: [profile], activeID: profile.id)
    }

    func observation(responseID: String? = nil, model: String = "gpt-6.1-sol") -> VyronOpenAIUsageObservation {
        VyronOpenAIUsageObservation(
            responseID: responseID, model: model, serviceTier: "default",
            result: .measured(VyronOpenAITokenUsage(
                inputTokens: 1_000, outputTokens: 500,
                inputDetails: VyronOpenAIInputTokenUsage(
                    cachedTokens: 200, cacheWrite30mTokens: 0, cacheWrite12hTokens: 0
                )
            ))
        )
    }

    func event(
        observation: VyronOpenAIUsageObservation? = nil,
        requestID: UUID = UUID(),
        connectionID: UUID? = nil,
        startedAt: Date? = nil
    ) -> VyronOpenAIUsageEvent {
        VyronOpenAIUsageEvent(
            connectionID: connectionID ?? profile.id, requestID: requestID,
            startedAt: startedAt ?? fixture.clock.date, observation: observation ?? self.observation()
        )
    }

    func cleanUp() async {
        balances.shutdown()
        await fixture.cleanUp()
    }
}
