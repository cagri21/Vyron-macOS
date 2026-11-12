import Foundation
import XCTest
@testable import Vyron
import VyronCore

@MainActor
final class VyronModelDownloadsTests: XCTestCase {
    func testPausePersistsAndResumeWaitsForCanceledTransferToSettle() async throws {
        let (downloads, store) = try makeDownloads()
        let tag = "deepseek-r1:8b"
        let first = VyronModelTransferTestOperation()
        let resumed = VyronModelTransferTestOperation()
        defer {
            downloads.shutdown()
            first.finish(.failure(CancellationError()))
            resumed.finish(.failure(CancellationError()))
        }

        downloads.start(VyronModelTransfer(tag: tag, kind: .pull), operation: first.operation)
        try await waitUntil { first.starts == 1 }
        let progress = ModelPullProgress(status: "Downloading", completed: 42, total: 100)
        first.emit(progress)
        try await waitUntil { downloads.progressByTag[tag] == progress }

        let duplicate = VyronModelTransfer(tag: "other:latest", kind: .pull)
        downloads.start(duplicate, operation: resumed.operation)
        XCTAssertEqual(downloads.active?.tag, tag)
        XCTAssertEqual(resumed.starts, 0)
        XCTAssertEqual(downloads.cancel(), .pull)
        XCTAssertFalse(downloads.isActive)
        XCTAssertEqual(store.load(), [tag])

        let retry = VyronModelTransfer(tag: tag, kind: .pull)
        downloads.start(retry, operation: resumed.operation)
        await Task.yield()
        XCTAssertEqual(downloads.active?.id, retry.id)
        XCTAssertEqual(resumed.starts, 0)
        first.emit(ModelPullProgress(status: "Late", completed: 98, total: 100))
        first.finish(.success(tag))
        try await waitUntil { resumed.starts == 1 }
        XCTAssertEqual(downloads.progressByTag[tag], progress)
        XCTAssertNil(first.result)
        XCTAssertEqual(first.refreshes, 0)

        resumed.finish(.success(tag))
        try await waitUntil { !downloads.isActive }
        XCTAssertEqual(try resumed.result?.get(), tag)
        XCTAssertEqual(resumed.refreshes, 1)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testFailedPullKeepsPartialProgressAndInstalledCatalogClearsItsPause() async throws {
        let (downloads, store) = try makeDownloads()
        let operation = VyronModelTransferTestOperation()
        let tag = "deepseek-r1:8b"
        defer {
            downloads.shutdown()
            operation.finish(.failure(CancellationError()))
        }
        downloads.start(VyronModelTransfer(tag: tag, kind: .pull), operation: operation.operation)
        try await waitUntil { operation.starts == 1 }
        let progress = ModelPullProgress(status: "Downloading", completed: 42, total: 100)
        operation.emit(progress)
        try await waitUntil { downloads.progressByTag[tag] == progress }
        operation.finish(.failure(URLError(.networkConnectionLost)))
        try await waitUntil { !downloads.isActive }

        XCTAssertThrowsError(try operation.result?.get()) { error in
            XCTAssertEqual((error as? URLError)?.code, .networkConnectionLost)
        }
        XCTAssertEqual(operation.refreshes, 0)
        XCTAssertEqual(downloads.progressByTag[tag], progress)
        XCTAssertEqual(store.load(), [tag])
        downloads.reconcileInstalledModels { $0 == tag }
        XCTAssertTrue(downloads.pausedTags.isEmpty)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testShutdownCancelsImportAndWaitsForItsCleanupWithoutPausingIt() async throws {
        let (downloads, store) = try makeDownloads()
        let operation = VyronModelTransferTestOperation()
        let importTransfer = VyronModelTransfer(tag: "local-import:latest", kind: .ggufImport)
        defer { operation.finish(.failure(CancellationError())) }
        downloads.start(importTransfer, operation: operation.operation)
        try await waitUntil { operation.starts == 1 }
        let cleanup = try XCTUnwrap(downloads.shutdown())

        XCTAssertTrue(cleanup.isCancelled)
        XCTAssertFalse(downloads.isActive)
        XCTAssertTrue(store.load().isEmpty)
        operation.finish(.failure(CancellationError()))
        await cleanup.value
        XCTAssertNil(operation.result)
        XCTAssertEqual(operation.refreshes, 0)
        downloads.start(importTransfer, operation: operation.operation)
        XCTAssertFalse(downloads.isActive)
    }

    private func makeDownloads() throws -> (VyronModelDownloads, VyronPausedModelDownloadsStore) {
        let suite = "VyronModelDownloadsTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { @MainActor in defaults.removePersistentDomain(forName: suite) }
        let store = VyronPausedModelDownloadsStore(defaults: defaults)
        return (VyronModelDownloads(pausedDownloads: store, storageDirectory: FileManager.default.temporaryDirectory), store)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The model transfer did not reach the expected state.")
        throw CancellationError()
    }
}
