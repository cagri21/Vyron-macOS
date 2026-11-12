import Foundation
import XCTest
@testable import VyronCore

final class VyronThinkingSettingsCompatibilityTests: XCTestCase {
    func testLegacyBooleanSettingsKeepTheirStorageKeyAndDecodeWithoutALevel() throws {
        let data = Data(#"{"contextTokens":8192,"maxOutputTokens":2048,"thinking":true}"#.utf8)
        let settings = try JSONDecoder().decode(ModelSettings.self, from: data)
        XCTAssertEqual(settings.thinking, true)
        XCTAssertNil(settings.thinkingLevel)
        let encoded = try JSONDecoder().decode(
            [String: DevelopmentJSONValue].self,
            from: JSONEncoder().encode(settings)
        )
        XCTAssertEqual(encoded["thinking"], .bool(true))
        XCTAssertNil(encoded["thinkingLevel"])
    }

    func testNamedLevelUsesAnAdditiveStringKeyAndSurvivesConnectionStorage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var settings = ModelSettings(contextTokens: 8_192, maxOutputTokens: 2_048)
        settings.thinkingLevel = .high
        let encoded = try JSONDecoder().decode(
            [String: DevelopmentJSONValue].self,
            from: JSONEncoder().encode(settings)
        )
        XCTAssertEqual(encoded["thinkingLevel"], .string("high"))
        XCTAssertNil(encoded["thinking"])
        let profile = ModelConnectionProfile(
            name: "Named level",
            kind: .ollama,
            endpoint: "http://localhost:11434",
            selectedModel: "fixture:latest",
            settings: settings
        )
        let state = ModelConnectionState(profiles: [profile], activeConnectionID: profile.id)
        let store = ModelConnectionStore(fileURL: directory.appendingPathComponent("connections.json"))
        try store.save(state)
        XCTAssertEqual(try store.load(), try state.validated())
    }

    func testConflictingThinkingValuesAndUnsupportedAdaptersAreRejected() {
        var conflicting = ModelSettings(thinking: true)
        conflicting.thinkingLevel = .high
        XCTAssertThrowsError(try conflicting.validated())
        for settings in [ModelSettings(thinking: false), namedSettings()] {
            let profile = ModelConnectionProfile(
                name: "Compatible",
                kind: .openAICompatible,
                endpoint: "https://models.example.test/v1",
                settings: settings
            )
            XCTAssertThrowsError(try profile.validated())
        }
    }

    private func namedSettings() -> ModelSettings {
        var settings = ModelSettings()
        settings.thinkingLevel = .low
        return settings
    }
}
