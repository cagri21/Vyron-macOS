import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

enum VyronOutputLimitTestSupport {
    static func incomplete(reason: String? = "max_output_tokens", output: [[String: Any]] = []) throws -> String {
        var response: [String: Any] = [
            "id": "resp_output_limit", "status": "incomplete", "output": output,
            "usage": ["input_tokens": 100, "output_tokens": 50]
        ]
        if let reason { response["incomplete_details"] = ["reason": reason] }
        return try VyronResponsesTestSupport.json(response)
    }

    static func generationBodies() async throws -> [[String: Any]] {
        let requests = await VyronResponsesTestURLProtocol.state.requests
        return try requests.filter { $0.url?.path == "/v1/responses" }.compactMap { request in
            let body = try VyronResponsesTestSupport.body(request)
            return body["tool_choice"] == nil ? body : nil
        }
    }

    static func client(recorder: VyronOpenAIUsageTestRecorder) throws -> VyronOpenAIResponsesClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [VyronResponsesTestURLProtocol.self]
        return try VyronOpenAIResponsesClient(
            connection: VyronResponsesTestSupport.profile(settings: ModelSettings(
                contextTokens: 32_768, maxOutputTokens: 4_096
            )),
            configuration: configuration, usageHandler: { await recorder.append($0) }
        )
    }
}
