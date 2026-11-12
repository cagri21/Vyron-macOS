import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

@MainActor
final class VyronDevelopmentImageObservationWireTests: XCTestCase {
    override func tearDown() async throws {
        await VyronResponsesTestURLProtocol.state.reset()
        try await super.tearDown()
    }

    func testOllamaDTOEncodesOnlySupportedFieldsWhileLocalMetadataRoundTrips() throws {
        let image = screenshot()
        let observation = DevelopmentMessage(
            observation: VyronDevelopmentImageObservation(
                tool: "vyron_mac_screenshot", textEvidence: "Reference text", isHistorical: true
            ),
            images: [image]
        )
        let local = try JSONDecoder().decode(DevelopmentMessage.self, from: JSONEncoder().encode(observation))
        XCTAssertEqual(local.imageObservation, observation.imageObservation)
        let encoded = try JSONEncoder().encode(VyronOllamaDevelopmentMessage(message: observation))
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(Set(wire.keys), ["role", "content", "images"])
        XCTAssertEqual(wire["role"] as? String, "user")
        XCTAssertEqual(wire["content"] as? String, observation.content)
        XCTAssertEqual(wire["images"] as? [String], [image.data.base64EncodedString()])
        XCTAssertNil(wire["image_observation"])
        XCTAssertNil(wire["imageObservation"])
        XCTAssertNil(wire["continuation"])
    }

    func testActualOllamaRequestPreservesPixelsAndOmitsNativeObservationMetadata() async throws {
        let image = screenshot()
        await VyronResponsesTestURLProtocol.state.reset { request, _ in
            switch request.url?.path {
            case "/api/tags":
                return VyronResponsesTestResponse(body:
                    #"{"models":[{"name":"tiny:1b","size":100,"capabilities":["tools","vision"]}]}"#
                )
            case "/api/show":
                return VyronResponsesTestResponse(body: #"{"capabilities":["tools","vision"]}"#)
            case "/api/chat":
                let body = try VyronResponsesTestSupport.body(request)
                let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
                let observation = try XCTUnwrap(messages.last)
                XCTAssertEqual(observation["role"] as? String, "user")
                XCTAssertEqual(observation["images"] as? [String], [image.data.base64EncodedString()])
                XCTAssertTrue((observation["content"] as? String)?.contains("not a new user request") == true)
                XCTAssertTrue(messages.allSatisfy { $0["image_observation"] == nil && $0["imageObservation"] == nil })
                return VyronResponsesTestResponse(body:
                    #"{"message":{"role":"assistant","content":"Observed app evidence"},"done":true}"#
                )
            default:
                XCTFail("Unexpected local model request")
                throw URLError(.unsupportedURL)
            }
        }
        let profile = ModelConnectionProfile(
            name: "Offline Ollama screenshot test",
            kind: .ollama,
            endpoint: "https://models.example.test",
            selectedModel: "tiny:1b"
        )
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        let client = try OllamaClient(connection: profile, configuration: configuration)
        let evidence = try XCTUnwrap(VyronDevelopmentToolImageContext.observation(
            tool: "vyron_mac_screenshot", images: [image]
        ))

        let result = try await client.developmentStep(model: "tiny:1b", messages: [evidence], mode: .agent)

        XCTAssertEqual(result.message.content, "Observed app evidence")
        XCTAssertEqual(evidence.imageObservation?.tool, "vyron_mac_screenshot")
    }

    private func screenshot() -> VyronImageAttachment {
        VyronImageAttachment(
            name: "App.png", mimeType: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        )
    }
}
