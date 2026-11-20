import VyronModelData
import VyronModelDomain

struct VyronAutoLocalServices {
    let makeProvider: @MainActor (ModelConnectionProfile) async throws -> any ModelProvider
    var assess: @Sendable (any ModelProvider, VyronAutoLocalRequest) async throws -> VyronAutoLocalDecision = {
        try await VyronAutoLocalRouter.route(using: $0, request: $1)
    }
}
