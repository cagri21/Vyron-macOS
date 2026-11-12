import Foundation
import VyronModelDomain

/// Telemetry is decoded independently so malformed usage cannot invalidate a valid answer.
enum VyronOpenAIUsageDecoding {
    static func observation(
        _ response: DevelopmentJSONValue?,
        model: String,
        compatible: Bool = false,
        requestedSpeed: VyronResponseSpeed = .standard
    ) -> VyronOpenAIUsageObservation {
        guard case .object(let object) = response else {
            return .init(responseID: nil, model: model, serviceTier: nil, result: .unavailable(.interrupted))
        }
        let responseID = string(object["id"])
        let selectedModel = string(object["model"]) ?? model
        let tier = string(object["service_tier"])
        let invalidTier = object["service_tier"] != nil && object["service_tier"] != .null && tier == nil
        let unknownFastTier = requestedSpeed == .fast && tier == nil
        return .init(
            responseID: responseID,
            model: selectedModel,
            serviceTier: tier,
            result: invalidTier || unknownFastTier
                ? .unavailable(.invalidUsage) : result(object["usage"], compatible: compatible)
        )
    }

    static func response(_ data: Data) -> DevelopmentJSONValue? {
        do { return try JSONDecoder().decode(DevelopmentJSONValue.self, from: data) } catch {
            // The normal transport decoder owns malformed response failures; telemetry stays optional.
            return nil
        }
    }

    private static func result(_ value: DevelopmentJSONValue?, compatible: Bool) -> VyronOpenAIUsageResult {
        guard let value, value != .null else { return .unavailable(.missingUsage) }
        guard case .object(let usage) = value else { return .unavailable(.invalidUsage) }
        let inputKey = compatible ? "prompt_tokens" : "input_tokens"
        let outputKey = compatible ? "completion_tokens" : "output_tokens"
        let detailsKey = compatible ? "prompt_tokens_details" : "input_tokens_details"
        guard let input = count(usage[inputKey]), let output = count(usage[outputKey]) else {
            return .unavailable(.invalidUsage)
        }
        let details: [String: DevelopmentJSONValue]
        if case .object(let found) = usage[detailsKey] {
            details = found
        } else if usage[detailsKey] == nil || usage[detailsKey] == .null {
            details = [:]
        } else {
            return .unavailable(.invalidUsage)
        }
        let outputDetailsKey = compatible ? "completion_tokens_details" : "output_tokens_details"
        if case .object(let outputDetails) = usage[outputDetailsKey], nonzero(outputDetails["audio_tokens"]) {
            return .unavailable(.unsupportedModality)
        }
        if nonzero(details["audio_tokens"]) { return .unavailable(.unsupportedModality) }
        guard let cached = optionalCount(details["cached_tokens"]),
            let write = optionalCount(details["cache_write_tokens"])
        else { return .unavailable(.invalidUsage) }
        let write30m: Int
        let write12h: Int
        if case .object(let found) = details["cache_write_tokens_details"] {
            guard let shortWrite = optionalCount(found["ttl_30m_tokens"]),
                let longWrite = optionalCount(found["ttl_12h_tokens"])
            else { return .unavailable(.invalidUsage) }
            write30m = shortWrite
            write12h = longWrite
        } else if details["cache_write_tokens_details"] == nil || details["cache_write_tokens_details"] == .null {
            // Responses requests omit cache TTL options, whose documented default is 30 minutes.
            // Chat Completions has no such verified lifetime contract in this adapter.
            write30m = compatible ? 0 : write
            write12h = 0
        } else {
            return .unavailable(.invalidUsage)
        }
        guard write30m <= input, write12h <= input - write30m,
            cached <= input - write30m - write12h,
            write == write30m + write12h
        else { return .unavailable(.invalidUsage) }
        return .measured(
            .init(
                inputTokens: input,
                outputTokens: output,
                inputDetails: .init(cachedTokens: cached, cacheWrite30mTokens: write30m, cacheWrite12hTokens: write12h)
            )
        )
    }

    private static func string(_ value: DevelopmentJSONValue?) -> String? {
        guard case .string(let text) = value, !text.isEmpty, text.utf8.count <= 512 else { return nil }
        return text
    }

    private static func count(_ value: DevelopmentJSONValue?) -> Int? {
        guard case .number(let number) = value, number.isFinite, number >= 0,
            number < 9_007_199_254_740_992, number.rounded(.towardZero) == number
        else { return nil }
        return Int(number)
    }

    private static func optionalCount(_ value: DevelopmentJSONValue?) -> Int? {
        value == nil || value == .null ? 0 : count(value)
    }

    private static func nonzero(_ value: DevelopmentJSONValue?) -> Bool {
        guard let value, value != .null else { return false }
        return count(value) != 0
    }
}
