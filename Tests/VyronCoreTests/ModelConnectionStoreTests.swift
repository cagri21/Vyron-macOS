import Foundation
import XCTest
@testable import VyronCore

final class ModelConnectionStoreTests: XCTestCase {
    func testProfilesExactVariantAndSettingsSurviveReloadWithoutCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelConnectionStore(fileURL: directory.appendingPathComponent("connections.json"))
        let profile = ModelConnectionProfile(name: "Custom coder", kind: .ollama, endpoint: "https://models.example.com/api/", selectedModel: "my-coder:8b-q8_0", settings: ModelSettings(contextTokens: 16_384, maxOutputTokens: 2_048, temperature: 0.2, topP: 0.85, thinking: false))
        let state = ModelConnectionState(profiles: [profile], activeConnectionID: profile.id, builtinSettings: ModelSettings(temperature: 0.3))
        try store.save(state)
        let loaded = try store.load()
        XCTAssertEqual(loaded, try state.validated())
        XCTAssertEqual(loaded.profiles.first?.selectedModel, "my-coder:8b-q8_0")
        XCTAssertEqual(loaded.profiles.first?.endpoint, "https://models.example.com")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any])
        let savedProfile = try XCTUnwrap((object["profiles"] as? [[String: Any]])?.first)
        XCTAssertNil(savedProfile["apiKey"])
        XCTAssertNil(savedProfile["key"])
        let permissions = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
    }

    func testMissingStateStartsWithBuiltinConnection() throws {
        let store = ModelConnectionStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertEqual(try store.load(), ModelConnectionState())
    }

    func testCorruptedSettingsArePreservedOnReadFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelConnectionStore(fileURL: directory.appendingPathComponent("connections.json"))
        let original = Data("{broken".utf8)
        try original.write(to: store.fileURL)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }

    func testInvalidReferencesAndDuplicateProfilesDoNotOverwriteSavedState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelConnectionStore(fileURL: directory.appendingPathComponent("connections.json"))
        try store.save(ModelConnectionState())
        let original = try Data(contentsOf: store.fileURL)
        XCTAssertThrowsError(try store.save(ModelConnectionState(activeConnectionID: UUID())))
        let profile = ModelConnectionProfile(name: "Local", kind: .ollama, endpoint: "http://localhost:11434", selectedModel: "coder:q4")
        XCTAssertThrowsError(try store.save(ModelConnectionState(profiles: [profile, profile])))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), original)
    }
}
