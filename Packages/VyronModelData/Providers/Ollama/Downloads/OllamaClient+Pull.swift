import Foundation
import VyronLocalization
import VyronModelDomain

extension OllamaClient {
    public func pull(
        model: String,
        onProgress: @escaping @Sendable (ModelPullProgress) -> Void
    ) async throws {
        try Self.validateModelName(model)
        let installed = try await catalog(path: "tags")
        if installed.contains(where: { Self.sameModelName($0.name, model) && $0.isRemote }) {
            throw LocalAIError.cloudModelNotAllowed
        }
        let request = try makeRequest(path: "pull", body: VyronOllamaPullRequest(model: model))
        let (bytes, response) = try await stream(request)
        defer { bytes.task.cancel() }
        try await validate(response: response, bytes: bytes)
        var finished = false
        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                let event: PullEvent = try Self.decodeLine(line)
                if let error = event.error { throw serverError(error) }
                guard let status = event.status else {
                    throw LocalAIError.invalidResponse(VyronModelDataText.missingDownloadStatus)
                }
                onProgress(ModelPullProgress(
                    status: status,
                    completed: event.completed,
                    total: event.total,
                    phase: VyronOllamaProgressStatus.phase(for: status)
                ))
                if status == VyronOllamaProgressStatus.success {
                    finished = true
                    break
                }
            }
            try Task.checkCancellation()
        } catch {
            throw Self.normalized(error)
        }
        guard finished else { throw LocalAIError.incompleteStream }
        let downloaded = try await catalog(path: "tags")
        if downloaded.contains(where: { Self.sameModelName($0.name, model) && $0.isRemote }) {
            throw LocalAIError.cloudModelNotAllowed
        }
    }
}
