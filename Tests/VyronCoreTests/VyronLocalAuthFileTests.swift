import Foundation
import Darwin
import XCTest
@testable import VyronCore

@MainActor
final class VyronLocalAuthFileTests: XCTestCase {
    func testOptionalConfigurationAndSecureBootstrapPersistAcrossStoreRestart() throws {
        let directory = try directory()
        let store = VyronLocalAuthFileConfigurationStore(baseDirectory: directory)
        XCTAssertNil(try store.load())
        try write(#"{"schema_version":1,"endpoint":"http://127.0.0.1:8327"}"#, name: "config.json", in: directory)
        let token = VyronLocalAuthToken.encode(Data(repeating: 4, count: 32))
        try write(token, name: "bootstrap.token", in: directory)
        XCTAssertEqual(try store.load()?.endpoint.absoluteString, "http://127.0.0.1:8327")
        XCTAssertEqual(try store.bootstrapToken(), Data(repeating: 4, count: 32))
        let restarted = VyronLocalAuthFileConfigurationStore(baseDirectory: directory)
        XCTAssertEqual(try restarted.bootstrapToken(), Data(repeating: 4, count: 32))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("bootstrap.token").path))
    }

    func testFilesRejectUnsafePermissionsSymlinksAndNonLoopbackEndpoints() throws {
        let directory = try directory()
        let store = VyronLocalAuthFileConfigurationStore(baseDirectory: directory)
        for endpoint in [
            "https://example.test", "http://localhost:8327", "http://127.0.0.1:8328",
            "http://127.0.0.1:8327/proxy", "http://127.0.0.1:8327?token=private"
        ] {
            try write("{\"schema_version\":1,\"endpoint\":\"\(endpoint)\"}", name: "config.json", in: directory)
            XCTAssertThrowsError(try store.load())
        }
        try write(#"{"schema_version":1,"endpoint":"http://127.0.0.1:8327"}"#, name: "config.json", in: directory)
        let config = directory.appendingPathComponent("config.json")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: config.path)
        XCTAssertThrowsError(try store.load())
        try FileManager.default.removeItem(at: config)
        let real = directory.appendingPathComponent("real-config.json")
        try write(#"{"schema_version":1,"endpoint":"http://127.0.0.1:8327"}"#, name: "real-config.json", in: directory)
        try FileManager.default.createSymbolicLink(at: config, withDestinationURL: real)
        XCTAssertThrowsError(try store.load())
        try write(String(repeating: "a", count: 43), name: "bootstrap.token", in: directory)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: directory.appendingPathComponent("bootstrap.token").path
        )
        XCTAssertThrowsError(try store.bootstrapToken())
    }

    func testRemovalIntentSurvivesRestartAndOnlyClearsExplicitCompletedID() throws {
        let directory = try directory()
        let store = VyronLocalAuthFileConfigurationStore(baseDirectory: directory)
        let first = UUID()
        let second = UUID()
        try store.recordRemoval(first)
        try store.recordRemoval(second)
        let restarted = VyronLocalAuthFileConfigurationStore(baseDirectory: directory)
        XCTAssertEqual(Set(try restarted.pendingRemovals()), [first, second])
        try restarted.completeRemoval(first)
        XCTAssertEqual(try store.pendingRemovals(), [second])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: directory.appendingPathComponent("pending-removals.json").path
        )
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testSymlinkAncestorsAreRejectedBeforeReadsOrDirectoryCreation() throws {
        let root = try directory()
        let actual = root.appendingPathComponent("actual", isDirectory: true)
        try FileManager.default.createDirectory(
            at: actual, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]
        )
        let link = root.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: actual)
        let store = VyronLocalAuthFileConfigurationStore(
            baseDirectory: link.appendingPathComponent("LocalAuth", isDirectory: true)
        )
        XCTAssertThrowsError(try store.load())
        XCTAssertThrowsError(try store.recordRemoval(UUID()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: actual.appendingPathComponent("LocalAuth").path))
    }

    func testNamedPipesAreRejectedWithoutWaitingForAWriter() throws {
        let directory = try directory()
        let store = VyronLocalAuthFileConfigurationStore(baseDirectory: directory)
        let start = ContinuousClock.now
        for name in ["config.json", "bootstrap.token", "pending-removals.json", "pending-removals.lock"] {
            let file = directory.appendingPathComponent(name)
            XCTAssertEqual(mkfifo(file.path, 0o600), 0)
            switch name {
            case "config.json": XCTAssertThrowsError(try store.load())
            case "bootstrap.token": XCTAssertThrowsError(try store.bootstrapToken())
            case "pending-removals.json": XCTAssertThrowsError(try store.pendingRemovals())
            default: XCTAssertThrowsError(try store.recordRemoval(UUID()))
            }
            try FileManager.default.removeItem(at: file)
        }
        XCTAssertLessThan(start.duration(to: .now), .seconds(1))
    }

    private func directory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func write(_ value: String, name: String, in directory: URL) throws {
        let file = directory.appendingPathComponent(name)
        try Data(value.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}
