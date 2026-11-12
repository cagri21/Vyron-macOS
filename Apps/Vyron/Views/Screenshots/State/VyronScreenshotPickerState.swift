import Combine
import Foundation

@MainActor
final class VyronScreenshotPickerState: ObservableObject {
    @Published private(set) var sources: [VyronScreenshotSource] = []
    @Published var selectedSourceID: String?
    @Published private(set) var isLoading = false
    @Published private(set) var isCapturing = false
    @Published private(set) var needsPermission = false
    @Published private(set) var errorMessage: String?

    private let captureService: any VyronScreenshotCapturing
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private var isActive = false

    init(captureService: any VyronScreenshotCapturing = VyronMacScreenshotCapture()) {
        self.captureService = captureService
    }

    var canCapture: Bool {
        isActive && !isLoading && !isCapturing && !needsPermission
            && sources.contains(where: { $0.id == selectedSourceID })
    }

    func start() {
        isActive = true
        refresh()
    }

    func refresh() {
        guard isActive, !isCapturing else { return }
        let currentGeneration = replaceOperation()
        isLoading = true
        errorMessage = nil
        needsPermission = false
        operation = Task { [weak self] in
            guard let self else { return }
            defer { finishOperation(currentGeneration) }
            do {
                let availableSources = try await captureService.sources()
                try Task.checkCancellation()
                guard isCurrent(currentGeneration) else { return }
                sources = availableSources
                if !sources.contains(where: { $0.id == selectedSourceID }) {
                    selectedSourceID = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(currentGeneration) else { return }
                sources = []
                selectedSourceID = nil
                recordFailure(error, isCapture: false)
            }
        }
    }

    func captureSelection(onCapture: @escaping (Data, String) -> Void) {
        guard canCapture, let source = sources.first(where: { $0.id == selectedSourceID }) else {
            if !isLoading && !isCapturing { errorMessage = VyronScreenshotText.selectionRequired }
            return
        }
        let currentGeneration = replaceOperation()
        isCapturing = true
        errorMessage = nil
        operation = Task { [weak self] in
            guard let self else { return }
            defer { finishOperation(currentGeneration) }
            do {
                let data = try await captureService.capture(source)
                try Task.checkCancellation()
                guard isCurrent(currentGeneration), selectedSourceID == source.id,
                    sources.contains(where: { $0 == source })
                else { return }
                onCapture(data, source.name)
            } catch is CancellationError {
                return
            } catch {
                guard isCurrent(currentGeneration) else { return }
                recordFailure(error, isCapture: true)
            }
        }
    }

    func requestPermission() {
        guard isActive, !isLoading, !isCapturing else { return }
        if captureService.requestPermission() {
            refresh()
        } else {
            needsPermission = true
            errorMessage = VyronScreenshotText.permissionRequired
        }
    }

    func openPermissionSettings() {
        guard isActive else { return }
        if !captureService.openPermissionSettings() {
            errorMessage = VyronScreenshotText.permissionRequired
        }
    }

    func stop() {
        isActive = false
        _ = replaceOperation()
        isLoading = false
        isCapturing = false
    }

    private func replaceOperation() -> UUID {
        operation?.cancel()
        operation = nil
        generation = UUID()
        return generation
    }

    private func isCurrent(_ expectedGeneration: UUID) -> Bool {
        isActive && generation == expectedGeneration && !Task.isCancelled
    }

    private func finishOperation(_ expectedGeneration: UUID) {
        guard generation == expectedGeneration else { return }
        operation = nil
        isLoading = false
        isCapturing = false
    }

    private func recordFailure(_ error: any Error, isCapture: Bool) {
        if let captureError = error as? VyronScreenshotCaptureError {
            switch captureError {
            case .permissionRequired:
                needsPermission = true
                errorMessage = VyronScreenshotText.permissionRequired
            case .sourceUnavailable:
                selectedSourceID = nil
                errorMessage = VyronScreenshotText.sourceUnavailable
            case .encodingFailed:
                errorMessage = VyronScreenshotText.encodingFailed
            }
        } else {
            errorMessage = isCapture
                ? VyronScreenshotText.captureFailed(error.localizedDescription)
                : VyronScreenshotText.loadFailed(error.localizedDescription)
        }
    }
}
