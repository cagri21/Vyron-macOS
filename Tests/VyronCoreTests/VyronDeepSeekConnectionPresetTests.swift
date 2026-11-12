import Foundation
import XCTest
@testable import VyronCore

final class VyronDeepSeekConnectionPresetTests: XCTestCase {
    func testPresetCreatesIndependentOfficialConnectionDrafts() throws {
        let first = VyronDeepSeekConnectionPreset.makeProfile()
        let second = VyronDeepSeekConnectionPreset.makeProfile()

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.name, "DeepSeek")
        XCTAssertEqual(first.kind, .openAICompatible)
        XCTAssertEqual(first.endpoint, "https://api.deepseek.com/v1")
        XCTAssertEqual(first.selectedModel, "deepseek-flash")
        XCTAssertEqual(first.settings, ModelSettings())
        XCTAssertEqual(try first.validated(), first)
    }

    func testDeepSeekSettingsAndConnectionIdentitySurviveMetadataReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronDeepSeekConnection-\(UUID())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelConnectionStore(fileURL: directory.appendingPathComponent("connections.json"))
        var profile = VyronDeepSeekConnectionPreset.makeProfile()
        profile.selectedModel = "deepseek-v4-pro"
        profile.settings = ModelSettings(
            contextTokens: 32_768,
            maxOutputTokens: 8_192,
            temperature: 0.25,
            topP: 0.99,
            thinking: true
        )
        let original = ModelConnectionState(profiles: [profile], activeConnectionID: profile.id)

        try store.save(original)
        let loaded = try store.load()

        XCTAssertEqual(loaded, original)
        XCTAssertEqual(loaded.activeConnectionID, profile.id)
        XCTAssertEqual(loaded.profiles.first?.id, profile.id)
        XCTAssertEqual(loaded.profiles.first?.settings.thinking, true)

        // The profile's serialized shape contains connection metadata only. API keys
        // remain in the separately keyed credential store, not an arbitrary JSON bag.
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: store.fileURL)) as? [String: Any]
        )
        XCTAssertEqual(Set(document.keys), ["profiles", "activeConnectionID", "builtinSettings"])
        let profiles = try XCTUnwrap(document["profiles"] as? [[String: Any]])
        let savedProfile = try XCTUnwrap(profiles.first)
        XCTAssertEqual(Set(savedProfile.keys), ["id", "name", "kind", "endpoint", "selectedModel", "settings"])
        let settings = try XCTUnwrap(savedProfile["settings"] as? [String: Any])
        XCTAssertEqual(Set(settings.keys), ["contextTokens", "maxOutputTokens", "temperature", "topP", "thinking"])
        XCTAssertEqual(savedProfile["id"] as? String, profile.id.uuidString)
    }

    func testAddingDeepSeekPreservesLegacyProfileAndBuiltinSettings() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronDeepSeekLegacy-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ModelConnectionStore(fileURL: directory.appendingPathComponent("connections.json"))
        let identifier = try XCTUnwrap(UUID(uuidString: "61EDB738-59C5-431D-814A-088F549AC2CD"))
        let legacy = Data("""
        {
          "profiles": [{
            "id": "61EDB738-59C5-431D-814A-088F549AC2CD",
            "name": "Existing custom server",
            "kind": "openAICompatible",
            "endpoint": "https://models.example.test/v1",
            "selectedModel": "vendor/exact-model-id",
            "settings": {"temperature": 0.25}
          }],
          "activeConnectionID": "61EDB738-59C5-431D-814A-088F549AC2CD",
          "builtinSettings": {"contextTokens": 16384, "thinking": false}
        }
        """.utf8)
        try legacy.write(to: store.fileURL)
        var state = try store.load()
        let existing = try XCTUnwrap(state.profiles.first)
        let builtinSettings = state.builtinSettings

        XCTAssertEqual(try Data(contentsOf: store.fileURL), legacy, "Loading must preserve the existing file.")
        state.profiles.append(VyronDeepSeekConnectionPreset.makeProfile())
        try store.save(state)
        let reopened = try store.load()

        XCTAssertEqual(reopened.activeConnectionID, identifier)
        XCTAssertEqual(reopened.profiles.first, existing)
        XCTAssertEqual(reopened.builtinSettings, builtinSettings)
        XCTAssertEqual(reopened.profiles.last?.selectedModel, "deepseek-flash")
        XCTAssertEqual(reopened.profiles.count, 2)
    }
}
