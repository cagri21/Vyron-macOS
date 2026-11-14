import Combine
import Foundation
import VyronCore

@MainActor
final class VyronModelDownloads: ObservableObject {
    @Published private(set) var active: VyronModelTransfer?
    @Published private(set) var progressByTag: [String: ModelPullProgress] = [:]
    @Published private(set) var pausedTags: Set<String>
    @Published private(set) var availableStorageBytes: Int64?
    @Published private(set) var isRemovingPreviousVariant = false

    private let pausedDownloads: VyronPausedModelDownloadsStore
    private let storageDirectory: URL
    private var task: Task<Void, Never>?
    private var stopped = false

    var isActive: Bool { active != nil }
    var isChangingPrecision: Bool {
        if case .precisionReplacement = active?.kind { return true }
        return false
    }

    init(pausedDownloads: VyronPausedModelDownloadsStore, storageDirectory: URL) {
        self.pausedDownloads = pausedDownloads
        self.storageDirectory = storageDirectory
        pausedTags = pausedDownloads.load()
    }

    func refreshStorageCapacity() {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: storageDirectory.path)
        availableStorageBytes = (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
    }

    func reconcileInstalledModels(_ isInstalled: (String) -> Bool) {
        savePausedTags(pausedTags.filter { !isInstalled($0) })
    }

    @discardableResult
    func start(_ transfer: VyronModelTransfer, operation: VyronModelTransferOperation) -> Bool {
        guard active == nil, !stopped else { return false }
        active = transfer
        if isChangingPrecision { progressByTag.removeValue(forKey: transfer.tag) }
        if transfer.kind == .pull { savePausedTags(pausedTags.subtracting([transfer.tag])) }
        let settling = task
        task = Task { @MainActor [weak self] in
            // A resumed download waits for the previous stream or import cleanup to settle.
            await settling?.value
            guard let self, self.isCurrent(transfer), !Task.isCancelled else { return }
            await self.run(transfer, operation: operation)
        }
        return true
    }

    func beginPrecisionRemoval(for transfer: VyronModelTransfer, afterSelecting select: () throws -> Void) throws {
        try Task.checkCancellation()
        guard isCurrent(transfer), isChangingPrecision else { throw CancellationError() }
        try select()
        isRemovingPreviousVariant = true
    }

    @discardableResult
    func cancel() -> VyronModelTransferKind? {
        guard let active, !isRemovingPreviousVariant else { return nil }
        if active.kind == .pull { savePausedTags(pausedTags.union([active.tag])) }
        self.active = nil
        task?.cancel()
        return active.kind
    }

    @discardableResult
    func shutdown() -> Task<Void, Never>? {
        stopped = true
        cancel()
        return task
    }

    private func run(_ transfer: VyronModelTransfer, operation: VyronModelTransferOperation) async {
        defer {
            if active?.id == transfer.id {
                active = nil
                task = nil
                isRemovingPreviousVariant = false
            }
        }
        do {
            let model = try await operation.execute { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.isCurrent(transfer), !self.isRemovingPreviousVariant else { return }
                    self.progressByTag[transfer.tag] = progress
                }
            }
            try Task.checkCancellation()
            guard isCurrent(transfer) else { return }
            await operation.refreshModels()
            try Task.checkCancellation()
            guard isCurrent(transfer) else { return }
            if transfer.kind == .pull { savePausedTags(pausedTags.subtracting([transfer.tag])) }
            operation.complete(.success(model))
        } catch {
            guard isCurrent(transfer), !Task.isCancelled else { return }
            if transfer.kind == .pull, (progressByTag[transfer.tag]?.completed ?? 0) > 0 {
                savePausedTags(pausedTags.union([transfer.tag]))
            }
            operation.complete(.failure(error))
        }
    }

    private func isCurrent(_ transfer: VyronModelTransfer) -> Bool {
        !stopped && active?.id == transfer.id
    }

    private func savePausedTags(_ tags: Set<String>) {
        guard pausedTags != tags else { return }
        pausedTags = tags
        pausedDownloads.save(tags)
    }
}
