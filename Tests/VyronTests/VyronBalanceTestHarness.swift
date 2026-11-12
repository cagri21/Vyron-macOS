import Foundation
import XCTest
import VyronCore
@testable import Vyron

@MainActor
final class VyronBalanceTestHarness {
    let clock: VyronBalanceTestClock
    let repository: VyronBalanceTestRepository
    let credentials: VyronBalanceTestCredentials
    let model: VyronConnectionBalancesModel

    init() {
        let clock = VyronBalanceTestClock()
        let repository = VyronBalanceTestRepository()
        let credentials = VyronBalanceTestCredentials()
        self.clock = clock
        self.repository = repository
        self.credentials = credentials
        model = VyronConnectionBalancesModel(dependencies: VyronConnectionBalanceDependencies(
            repository: repository,
            credential: { try credentials.read($0) },
            clock: VyronConnectionBalanceClock(now: { clock.date }, sleep: { try await clock.sleep($0) })
        ))
    }

    func profile(
        _ name: String = "DeepSeek",
        endpoint: String = "https://api.deepseek.com/v1"
    ) -> ModelConnectionProfile {
        ModelConnectionProfile(name: name, kind: .openAICompatible, endpoint: endpoint, selectedModel: "fixture-model")
    }

    func snapshot(
        amount: Decimal = 12,
        scope: VyronConnectionBalanceScope = .account
    ) -> VyronConnectionBalanceSnapshot {
        VyronConnectionBalanceSnapshot(
            amounts: [VyronConnectionBalanceAmount(currency: "USD", amount: amount)],
            scope: scope, checkedAt: clock.date
        )
    }

    func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTFail("The offline balance lifecycle did not reach its expected state.")
        throw CancellationError()
    }

    func cleanUp() async {
        model.shutdown()
        clock.cancelAll()
        await repository.finishAll()
        for _ in 0..<10 { await Task.yield() }
    }

    func settle() async throws {
        for _ in 0..<20 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(1))
    }
}
