import Foundation
import VyronCore
import XCTest
@testable import Vyron

final class VyronModelConnectionServerChoiceTests: XCTestCase {
    func testHostedSelectionsFillTheServerAndModelForAnEmptyDraft() {
        let draft = ModelConnectionProfile(name: "", kind: .openAICompatible, endpoint: "")

        let gemini = VyronModelConnectionServerChoice.gemini.applying(to: draft)
        XCTAssertEqual(gemini.name, "Gemini")
        XCTAssertEqual(gemini.endpoint, "https://generativelanguage.googleapis.com/v1beta/openai")
        XCTAssertEqual(gemini.selectedModel, "gemini-3.8-flash")
        XCTAssertEqual(VyronModelConnectionServerChoice(profile: gemini), .gemini)

        let meta = VyronModelConnectionServerChoice.meta.applying(to: gemini)
        XCTAssertEqual(meta.name, "Meta")
        XCTAssertEqual(meta.endpoint, "https://api.meta.ai/v1")
        XCTAssertEqual(meta.selectedModel, "muse-spark-1.3")
        XCTAssertEqual(VyronModelConnectionServerChoice(profile: meta), .meta)
    }

    func testHostedSelectionRetainsProfileIdentityAndCompatibleStorage() throws {
        var original = ModelConnectionProfile(
            name: "My connection",
            kind: .openAICompatible,
            endpoint: "https://models.example.test/v1"
        )
        original.selectedModel = "custom-model"
        original.settings.maxOutputTokens = 2_048

        for choice in [VyronModelConnectionServerChoice.gemini, .meta] {
            let draft = choice.applying(to: original)
            let encoded = try JSONEncoder().encode(draft)
            let saved = try JSONDecoder().decode(ModelConnectionProfile.self, from: encoded)
            XCTAssertEqual(saved.id, original.id)
            XCTAssertEqual(saved.name, original.name)
            XCTAssertEqual(saved.settings, original.settings)
            XCTAssertEqual(saved.kind, .openAICompatible)
            XCTAssertEqual(VyronModelConnectionServerChoice(profile: saved), choice)
        }
    }

    func testSwitchingFromAHostedPresetToGenericClearsItsEndpointAndModel() {
        let hosted = VyronMetaConnectionPreset.makeProfile()
        let generic = VyronModelConnectionServerChoice.openAICompatible.applying(to: hosted)

        XCTAssertEqual(generic.id, hosted.id)
        XCTAssertEqual(generic.kind, .openAICompatible)
        XCTAssertEqual(generic.endpoint, "")
        XCTAssertEqual(generic.selectedModel, "")
        XCTAssertEqual(VyronModelConnectionServerChoice(profile: generic), .openAICompatible)
    }

    func testOfficialEndpointMatchingRequiresTheCorrectProtocolHostAndPath() {
        var profile = ModelConnectionProfile(
            name: "Custom display name",
            kind: .openAICompatible,
            endpoint: " HTTPS://GENERATIVELANGUAGE.GOOGLEAPIS.COM:443/v1beta/openai/ "
        )
        XCTAssertEqual(VyronModelConnectionServerChoice(profile: profile), .gemini)

        profile.endpoint = "https://API.META.AI/v1/"
        XCTAssertEqual(VyronModelConnectionServerChoice(profile: profile), .meta)

        for endpoint in [
            "https://generativelanguage.googleapis.com.example.test/v1beta/openai",
            "https://generativelanguage.googleapis.com/v1beta/openai-proxy",
            "https://api.meta.ai.example.test/v1",
            "https://api.meta.ai:8443/v1"
        ] {
            profile.endpoint = endpoint
            XCTAssertEqual(VyronModelConnectionServerChoice(profile: profile), .openAICompatible, endpoint)
        }

        profile.endpoint = VyronMetaConnectionPreset.endpoint
        profile.kind = .anthropic
        XCTAssertEqual(VyronModelConnectionServerChoice(profile: profile), .anthropic)
    }
}
