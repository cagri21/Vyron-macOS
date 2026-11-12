import Foundation
import XCTest
@testable import VyronCore
@testable import VyronModelData

final class VyronOpenAIUsageDecodingTests: XCTestCase {
    func testUsageSeparatesCachedReadsAndWritesWithoutAddingReasoningAgain() throws {
        let json = #"""
        {"id":"resp_usage","model":"gpt-6.1-sol-2026-10-07","service_tier":"default","usage":{
          "input_tokens":1000,"output_tokens":120,"output_tokens_details":{"reasoning_tokens":100},
          "input_tokens_details":{"cached_tokens":200,"cache_write_tokens":300,
            "cache_write_tokens_details":{"ttl_30m_tokens":100,"ttl_12h_tokens":200}}
        }}
        """#
        let observation = decode(json)
        XCTAssertEqual(observation.responseID, "resp_usage")
        XCTAssertEqual(observation.model, "gpt-6.1-sol-2026-10-07")
        XCTAssertEqual(observation.serviceTier, "default")
        XCTAssertEqual(observation.result, .measured(.init(
            inputTokens: 1000,
            outputTokens: 120,
            inputDetails: .init(cachedTokens: 200, cacheWrite30mTokens: 100, cacheWrite12hTokens: 200)
        )))
    }

    func testCompatibleUsesReturnedPromptAndCompletionTokens() {
        let observation = VyronOpenAIUsageDecoding.observation(
            VyronOpenAIUsageDecoding.response(Data(#"""
            {"id":"chat-usage","model":"gpt-4.1","usage":{
              "prompt_tokens":10,"completion_tokens":5,"prompt_tokens_details":{"cached_tokens":4}
            }}
            """#.utf8)),
            model: "requested-model", compatible: true
        )
        XCTAssertEqual(observation.result, .measured(.init(
            inputTokens: 10, outputTokens: 5,
            inputDetails: .init(cachedTokens: 4, cacheWrite30mTokens: 0, cacheWrite12hTokens: 0)
        )))
    }

    func testMissingMalformedAndInterruptedUsageRemainDistinctFromZeroCost() {
        XCTAssertEqual(decode("{}").result, .unavailable(.missingUsage))
        XCTAssertEqual(decode(#"{"usage":null}"#).result, .unavailable(.missingUsage))
        XCTAssertEqual(decode(#"{"usage":"invalid"}"#).result, .unavailable(.invalidUsage))
        XCTAssertEqual(decode("broken json").result, .unavailable(.interrupted))
        XCTAssertEqual(decode(#"{"usage":{"input_tokens":0,"output_tokens":0}}"#).result, .measured(.init(
            inputTokens: 0, outputTokens: 0,
            inputDetails: .init(cachedTokens: 0, cacheWrite30mTokens: 0, cacheWrite12hTokens: 0)
        )))
    }

    func testImpossibleOrUnpricedUsageIsRejected() {
        for usage in [
            #"{"input_tokens":-1,"output_tokens":2}"#,
            #"{"input_tokens":true,"output_tokens":2}"#,
            #"{"input_tokens":1.5,"output_tokens":2}"#,
            #"{"input_tokens":9007199254740992,"output_tokens":2}"#,
            #"{"input_tokens":10,"output_tokens":2,"input_tokens_details":{"cached_tokens":11}}"#,
            #"{"input_tokens":10,"output_tokens":2,"input_tokens_details":{"cache_write_tokens":1,"cache_write_tokens_details":{"ttl_30m_tokens":2}}}"#,
            #"{"input_tokens":10,"output_tokens":2,"input_tokens_details":{"cached_tokens":"2"}}"#
        ] {
            XCTAssertEqual(decode("{\"usage\":\(usage)}").result, .unavailable(.invalidUsage), usage)
        }
        XCTAssertEqual(decode(#"""
        {"usage":{"input_tokens":10,"output_tokens":2,"input_tokens_details":{"audio_tokens":1}}}
        """#).result, .unavailable(.unsupportedModality))
    }

    func testAggregateResponsesCacheWritesUseTheRequestedDefaultLifetime() {
        let observation = decode(#"""
        {"usage":{"input_tokens":10,"output_tokens":2,"input_tokens_details":{"cache_write_tokens":4}}}
        """#)
        XCTAssertEqual(observation.result, .measured(.init(
            inputTokens: 10, outputTokens: 2,
            inputDetails: .init(cachedTokens: 0, cacheWrite30mTokens: 4, cacheWrite12hTokens: 0)
        )))
    }

    private func decode(_ json: String) -> VyronOpenAIUsageObservation {
        VyronOpenAIUsageDecoding.observation(
            VyronOpenAIUsageDecoding.response(Data(json.utf8)), model: "fallback-model"
        )
    }
}
