import VyronCore

struct VyronModelTransferOperation {
    let execute: @MainActor (@escaping @Sendable (ModelPullProgress) -> Void) async throws -> String
    let refreshModels: @MainActor () async -> Void
    let complete: @MainActor (Result<String, any Error>) -> Void
}
