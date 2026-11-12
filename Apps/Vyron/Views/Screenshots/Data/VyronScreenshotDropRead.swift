import AppKit

@MainActor
final class VyronScreenshotDropRead {
    private let provider: NSItemProvider
    private let typeIdentifier: String
    private var continuation: CheckedContinuation<Data, any Error>?
    private var progress: Progress?

    init(provider: NSItemProvider, typeIdentifier: String) {
        self.provider = provider
        self.typeIdentifier = typeIdentifier
    }

    func load() async throws -> Data {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                progress = provider.loadDataRepresentation(
                    forTypeIdentifier: typeIdentifier
                ) { [weak self] data, error in
                    Task { @MainActor [weak self] in self?.complete(data: data, error: error) }
                }
            }
        } onCancel: {
            Task { @MainActor in self.cancel() }
        }
    }

    private func complete(data: Data?, error: (any Error)?) {
        guard let continuation else { return }
        self.continuation = nil
        progress = nil
        if let error {
            continuation.resume(throwing: error)
        } else if let data {
            if data.count > VyronScreenshotLimits.maximumImportBytes {
                continuation.resume(throwing: VyronScreenshotImportError.tooLarge)
            } else {
                continuation.resume(returning: data)
            }
        } else {
            continuation.resume(throwing: VyronScreenshotImportError.invalidImage)
        }
    }

    private func cancel() {
        let pending = continuation
        continuation = nil
        progress?.cancel()
        progress = nil
        pending?.resume(throwing: CancellationError())
    }
}
