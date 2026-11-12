import CoreFoundation
import Foundation
import VyronModelDomain

struct VyronOllamaResponseMetrics: Sendable {
    let finishReason: String
    let generatedTokens: Int?
    let promptTokens: Int?

    static func decode(data: Data, reason: String?) -> Self {
        let safeReason: String
        switch reason {
        case "stop", "length", "load", "unload": safeReason = reason ?? "missing"
        case nil: safeReason = "missing"
        default: safeReason = "other"
        }
        do {
            // Statistics are optional transport data; never retain the object or its response text.
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return Self(
                finishReason: safeReason,
                generatedTokens: count(object?["eval_count"]),
                promptTokens: count(object?["prompt_eval_count"])
            )
        } catch {
            // Malformed optional statistics cannot invalidate an already decoded inference envelope.
            return Self(finishReason: safeReason, generatedTokens: nil, promptTokens: nil)
        }
    }

    private static func count(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value <= Double(Int32.max), value.rounded(.towardZero) == value else {
            return nil
        }
        return Int(value)
    }
}
