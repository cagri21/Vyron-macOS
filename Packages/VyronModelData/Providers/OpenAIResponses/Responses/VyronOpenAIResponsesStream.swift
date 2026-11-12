import Foundation
import VyronLocalization
import VyronModelDomain

struct VyronOpenAIResponsesStream {
    private var line = Data()
    private var payload: [String] = []
    private var payloadBytes = 0
    private(set) var output = ""
    private(set) var completed = false
    private(set) var terminalResponse: DevelopmentJSONValue?

    init() {}

    mutating func append(_ byte: UInt8) throws -> String {
        guard !completed else { return "" }
        if byte == 10 {
            let token = try consumeLine()
            line.removeAll(keepingCapacity: true)
            return token
        }
        guard line.count < VyronOpenAIResponsesLimits.eventBytes else { throw tooLarge }
        line.append(byte)
        return ""
    }

    mutating func finish() throws -> String {
        var token = ""
        if !line.isEmpty { token += try consumeLine(); line.removeAll() }
        if !payload.isEmpty { token += try consumeEvent() }
        guard completed else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.responseStreamIncomplete)
        }
        return token
    }

    private var tooLarge: ModelProviderError { .invalidResponse(VyronModelDataText.responseStreamTooLarge) }

    private mutating func consumeLine() throws -> String {
        guard let raw = String(data: line, encoding: .utf8) else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.invalidStreamingText)
        }
        let value = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
        if value.isEmpty { return try consumeEvent() }
        guard value.hasPrefix("data:") else { return "" }
        let data = String(value.dropFirst(5).drop(while: { $0 == " " }))
        payloadBytes += data.utf8.count
        guard payloadBytes <= VyronOpenAIResponsesLimits.eventBytes else { throw tooLarge }
        payload.append(data)
        return ""
    }

    private mutating func consumeEvent() throws -> String {
        guard !payload.isEmpty else { return "" }
        let data = Data(payload.joined(separator: "\n").utf8)
        payload.removeAll(keepingCapacity: true)
        payloadBytes = 0
        let event = try JSONDecoder().decode([String: DevelopmentJSONValue].self, from: data)
        guard case .string(let type) = event["type"] else {
            throw ModelProviderError.invalidResponse(VyronModelDataText.invalidStreamEvent)
        }
        switch type {
        case "response.output_text.delta":
            guard case .string(let delta) = event["delta"] else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.invalidStreamTextUpdate)
            }
            guard output.utf8.count + delta.utf8.count <= VyronOpenAIResponsesLimits.responseBytes else {
                throw tooLarge
            }
            output += delta
            return delta
        case "response.completed":
            guard let response = event["response"] else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.missingCompletedResponse)
            }
            terminalResponse = response
            let document = try JSONDecoder().decode(
                VyronOpenAIResponsesDocument.self,
                from: JSONEncoder().encode(response)
            )
            let result = try VyronOpenAIResponsesOutput(items: document.completedOutput())
            guard result.message.toolCalls?.isEmpty != false,
                output.isEmpty || output == result.message.content
            else {
                throw ModelProviderError.invalidResponse(
                    VyronModelDataText.inconsistentStreamAnswer
                )
            }
            completed = true
            if output.isEmpty { output = result.message.content; return output }
            return ""
        case "response.incomplete":
            terminalResponse = event["response"]
            guard let response = terminalResponse else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.missingIncompleteResponse)
            }
            let document = try JSONDecoder().decode(
                VyronOpenAIResponsesDocument.self,
                from: JSONEncoder().encode(response)
            )
            _ = try document.completedOutput()
            throw ModelProviderError.invalidResponse(VyronModelDataText.modelIncompleteResponse)
        case "response.failed", "error":
            terminalResponse = event["response"]
            throw ModelProviderError.invalidResponse(VyronModelDataText.serverResponseError)
        default:
            return ""
        }
    }
}
