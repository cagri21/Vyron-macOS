import Combine
import Foundation
import XCTest
@testable import Vyron
@testable import VyronModelData

@MainActor
final class VyronModelPrecisionChangeTests: XCTestCase {
    private let original = VyronModelPrecisionTransport.original
    private let alias = VyronModelPrecisionTransport.alias
    private let replacement = VyronModelPrecisionTransport.replacement

    func testAlreadyInstalledReplacementIsVerifiedAndSelectedBeforeExactRemoval() async throws {
        let stub = VyronModelPrecisionTransport(replacementInstalled: true)
        try await withModel(stub, port: 29_101) { model, client in
            try await startSwitch(model, client: client)
            try await waitUntil { !model.modelDownloads.isActive }

            XCTAssertEqual(stub.operations, ["probe \(replacement)", "select \(replacement)", "delete \(original)"])
            XCTAssertEqual(stub.tags, [alias, replacement])
            XCTAssertEqual(model.modelSelection.selectedModel, replacement)
        }
    }

    func testMissingReplacementIsDownloadedBeforeVerificationAndSelection() async throws {
        let stub = VyronModelPrecisionTransport()
        try await withModel(stub, port: 29_102) { model, client in
            try await startSwitch(model, client: client)
            try await waitUntil { !model.modelDownloads.isActive }

            XCTAssertEqual(stub.operations, [
                "pull \(replacement)", "probe \(replacement)", "select \(replacement)", "delete \(original)"
            ])
            XCTAssertEqual(stub.tags, [alias, replacement])
            XCTAssertEqual(model.modelSelection.selectedModel, replacement)
        }
    }

    func testFailedVerificationKeepsOriginalInstalledAndSelected() async throws {
        let stub = VyronModelPrecisionTransport(failProbe: true)
        try await withModel(stub, port: 29_103) { model, client in
            try await startSwitch(model, client: client)
            try await waitUntil { !model.modelDownloads.isActive }

            XCTAssertEqual(stub.operations, ["pull \(replacement)", "probe \(replacement)"])
            XCTAssertTrue(stub.tags.contains(original))
            XCTAssertEqual(model.modelSelection.selectedModel, original)
        }
    }

    func testFailedDownloadKeepsOriginalInstalledAndSelected() async throws {
        let stub = VyronModelPrecisionTransport(failPull: true)
        try await withModel(stub, port: 29_104) { model, client in
            try await startSwitch(model, client: client)
            try await waitUntil { !model.modelDownloads.isActive }

            XCTAssertEqual(stub.operations, ["pull \(replacement)"])
            XCTAssertEqual(stub.tags, [alias, original])
            XCTAssertEqual(model.modelSelection.selectedModel, original)
        }
    }

    func testMissingInstalledOnlyReplacementDoesNotPullOrRemoveAnything() async throws {
        let stub = VyronModelPrecisionTransport()
        try await withModel(stub, port: 29_106) { model, client in
            try await startSwitch(model, client: client, mayDownloadReplacement: false)
            try await waitUntil { !model.modelDownloads.isActive }

            XCTAssertTrue(stub.operations.isEmpty)
            XCTAssertEqual(stub.tags, [alias, original])
            XCTAssertEqual(model.modelSelection.selectedModel, original)
        }
    }

    func testCancelingDownloadKeepsOriginalInstalledAndSelected() async throws {
        let stub = VyronModelPrecisionTransport(holdPull: true)
        try await withModel(stub, port: 29_105) { model, client in
            try await startSwitch(model, client: client)
            try await waitUntil { stub.operations == ["pull \(replacement)"] }
            model.cancelDownload()
            await model.modelDownloads.shutdown()?.value

            XCTAssertFalse(model.modelDownloads.isActive)
            XCTAssertEqual(stub.operations, ["pull \(replacement)"])
            XCTAssertEqual(stub.tags, [alias, original])
            XCTAssertEqual(model.modelSelection.selectedModel, original)
        }
    }

    private func startSwitch(
        _ model: AppModel, client: OllamaClient, mayDownloadReplacement: Bool = true
    ) async throws {
        let identity = try await client.installedModelIdentity(named: original)
        let published = ModelSourceVariant(
            id: replacement, name: replacement, ollamaTag: replacement, quantization: "Q8_0", parameterSize: "27B"
        )
        let change = VyronModelPrecisionChange(
            original: identity, replacement: published, connectionRevision: model.modelSelection.connectionRevision,
            mayDownloadReplacement: mayDownloadReplacement
        )
        XCTAssertTrue(model.changeModelPrecision(change))
        XCTAssertTrue(model.modelDownloads.isActive)
    }

    private func withModel(
        _ stub: VyronModelPrecisionTransport,
        port: Int,
        run: @MainActor (AppModel, OllamaClient) async throws -> Void
    ) async throws {
        let suite = "VyronModelPrecisionTests-\(UUID())"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        VyronModelPrecisionURLProtocol.register(stub, port: port)
        defer {
            VyronModelPrecisionURLProtocol.unregister(port: port)
            defaults.removePersistentDomain(forName: suite)
            do { try FileManager.default.removeItem(at: directory) }
            catch { XCTFail("Could not remove precision test files: \(error)") }
        }

        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)"))
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronModelPrecisionURLProtocol.self]
        let client = OllamaClient(baseURL: url, configuration: configuration)
        defaults.set(original, forKey: VyronUserDefaultsKey.selectedLocalModel.rawValue)
        defaults.set(false, forKey: VyronUserDefaultsKey.automaticModelSelection.rawValue)
        let model = AppModel(
            storagePaths: VyronAppStoragePaths(directory: directory), preferences: defaults,
            modelOverrides: VyronAppModelOverrides(builtinClient: client)
        )
        model.modelSelection.models = try await client.models()
        model.modelSelection.isConnected = true
        let selection = model.modelSelection.$selectedModel.sink { stub.recordSelection($0) }
        defer {
            selection.cancel()
            model.cancelModelFeatureVerification()
            model.modelDownloads.shutdown()
        }
        try await run(model, client)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        for _ in 0..<500 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The precision change did not reach its expected state.")
        throw CancellationError()
    }
}
