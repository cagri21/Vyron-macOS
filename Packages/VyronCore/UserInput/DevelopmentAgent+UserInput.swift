import Foundation

extension DevelopmentAgent {
    static func askUser(
        _ request: VyronUserInputRequest,
        using handler: @escaping @Sendable (VyronUserInputRequest) async throws -> VyronUserInputResponse
    ) async throws -> VyronUserInputResponse {
        let gate = VyronUserInputGate()
        let response = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard gate.install(continuation) else { return }
                let worker = Task {
                    do {
                        try Task.checkCancellation()
                        gate.resolve(.success(try await handler(request)))
                    } catch {
                        gate.resolve(.failure(error))
                    }
                }
                gate.attach(worker)
            }
        } onCancel: {
            gate.resolve(.failure(CancellationError()))
        }
        try Task.checkCancellation()
        try VyronUserInputTool.validate(response, for: request)
        return response
    }
}
