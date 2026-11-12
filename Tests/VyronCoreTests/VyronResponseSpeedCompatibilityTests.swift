import Foundation
import XCTest
@testable import VyronCore

final class VyronResponseSpeedCompatibilityTests: XCTestCase {
    func testOlderSettingsDecodeAndTheirDefaultEncodingRemainsUnchanged() throws {
        let source = Data(#"{"contextTokens":32768,"maxOutputTokens":4096,"thinking":false}"#.utf8)
        let settings = try JSONDecoder().decode(ModelSettings.self, from: source)
        XCTAssertNil(settings.responseSpeed)
        XCTAssertEqual(settings.contextTokens, 32_768)
        XCTAssertEqual(settings.maxOutputTokens, 4_096)
        XCTAssertEqual(settings.thinking, false)
        let encoded = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings))
            as? [String: Any])
        XCTAssertNil(encoded["responseSpeed"])
        XCTAssertEqual(Set(encoded.keys), ["contextTokens", "maxOutputTokens", "thinking"])
    }

    func testSelectedSpeedRoundTripsWithoutReplacingOtherConnectionSettingsOrIdentity() throws {
        for speed in VyronResponseSpeed.allCases {
            var settings = ModelSettings(contextTokens: 16_384, maxOutputTokens: 1_024)
            settings.responseSpeed = speed
            let profile = VyronResponsesTestSupport.profile(settings: settings)
            let state = ModelConnectionState(profiles: [profile], activeConnectionID: profile.id)
            let restored = try JSONDecoder().decode(ModelConnectionState.self, from: JSONEncoder().encode(state))
            XCTAssertEqual(restored, state)
            XCTAssertEqual(restored.profiles.first?.settings.responseSpeed, speed)
            XCTAssertEqual(restored.profiles.first?.id, profile.id)
        }
    }

    func testFastOnlyAppliesToReviewedOfficialOpenAIModels() {
        var profile = VyronResponsesTestSupport.profile()
        profile.settings.responseSpeed = .fast
        XCTAssertTrue(VyronResponseSpeedPolicy.supportsFast(connection: profile, model: "gpt-6.1-sol"))
        XCTAssertEqual(VyronResponseSpeedPolicy.effectiveSpeed(connection: profile, model: "gpt-6.1-sol"), .fast)
        for name in ["qwen3-coder:30b", "unknown-model", "gpt-6.1-sol-proxy", "gpt-6.1-sol-2099-01-01"] {
            XCTAssertFalse(VyronResponseSpeedPolicy.supportsFast(connection: profile, model: name))
            XCTAssertEqual(VyronResponseSpeedPolicy.effectiveSpeed(connection: profile, model: name), .standard)
        }
        for endpoint in ["https://models.example.test/v1", "http://localhost:1234/v1", "https://api.openai.com.evil/v1"] {
            profile.endpoint = endpoint
            XCTAssertFalse(VyronResponseSpeedPolicy.supportsFast(connection: profile, model: "gpt-6.1-sol"))
            XCTAssertEqual(VyronResponseSpeedPolicy.effectiveSpeed(connection: profile, model: "gpt-6.1-sol"), .standard)
        }
        XCTAssertFalse(VyronResponseSpeedPolicy.supportsFast(connection: nil, model: "gpt-6.1-sol"))
    }
}
