import Foundation
import VyronLocalization
import VyronModelDomain

/// Variant JSON objects stay at the Responses transport boundary, including opaque encrypted reasoning.
enum VyronOpenAIResponsesWire {
    static func chatInput(_ messages: [ChatMessage], systemPrompt: String?) throws -> [DevelopmentJSONValue] {
        try VyronImageAttachment.validate(messages: messages)
        var input: [DevelopmentJSONValue] = []
        if let systemPrompt, !systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            input.append(message(role: "system", content: systemPrompt))
        }
        for item in messages {
            guard ["system", "user", "assistant"].contains(item.role) else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.unsupportedMessageRole)
            }
            guard let images = item.images, !images.isEmpty else {
                input.append(message(role: item.role, content: item.content))
                continue
            }
            var parts: [DevelopmentJSONValue] = [
                .object(["type": .string("input_text"), "text": .string(item.content)])
            ]
            parts += images.map { image in
                .object([
                    "type": .string("input_image"),
                    "image_url": .string("data:\(image.mimeType);base64,\(image.data.base64EncodedString())")
                ])
            }
            input.append(.object(["role": .string(item.role), "content": .array(parts)]))
        }
        return input
    }

    static func message(role: String, content: String) -> DevelopmentJSONValue {
        .object(["role": .string(role), "content": .string(content)])
    }

    static func tool(_ definition: DevelopmentToolDefinition) throws -> DevelopmentJSONValue {
        let parameters = try JSONDecoder().decode(
            DevelopmentJSONValue.self,
            from: JSONEncoder().encode(definition.function.parameters)
        )
        return .object([
            "type": .string("function"), "name": .string(definition.function.name),
            "description": .string(definition.function.description), "parameters": parameters, "strict": .bool(false)
        ])
    }

    static func request(
        model: String,
        input: [DevelopmentJSONValue],
        settings: ModelSettings,
        options: VyronOpenAIResponsesOptions
    ) throws -> Data {
        let tools = try options.tools.map(tool)
        let desired = options.generation.maximumOutputTokens
        let context = VyronOpenAIResponsesModelBudget.contextTokens(for: model, override: settings.contextTokens)
        let inputTokens: Int
        if let measured = options.measuredInputTokens {
            guard (0...VyronOpenAIResponsesLimits.requestBytes).contains(measured) else {
                throw ModelProviderError.invalidResponse(VyronModelDataText.invalidInputTokenCount)
            }
            inputTokens = measured
        } else {
            inputTokens = try JSONEncoder().encode(budgetInput(input)).count + JSONEncoder().encode(tools).count
        }
        let maximum = min(desired, context - inputTokens - VyronOpenAIResponsesLimits.contextOverhead)
        guard maximum >= (tools.isEmpty ? 1 : VyronOpenAIResponsesLimits.minimumDevelopmentOutput) else {
            throw DevelopmentAgentError.contextBudget
        }
        // Development must compact context rather than silently consume its reserved generation allowance.
        guard tools.isEmpty || maximum == desired else { throw DevelopmentAgentError.contextBudget }
        var body: [String: DevelopmentJSONValue] = [
            "model": .string(model), "input": .array(input), "stream": .bool(options.generation.stream),
            "service_tier": .string(VyronOpenAIResponseSpeed.serviceTier(settings: settings, model: model)),
            "store": .bool(false),
            "include": .array([.string("reasoning.encrypted_content")]),
            "max_output_tokens": .number(Double(maximum))
        ]
        if let effort = options.generation.reasoningEffort { body["reasoning"] = .object(["effort": .string(effort)]) }
        if !tools.isEmpty { body["tools"] = .array(tools) }
        if let name = options.forcedTool {
            body["tool_choice"] = .object(["type": .string("function"), "name": .string(name)])
        }
        let data = try JSONEncoder().encode(body)
        guard data.count <= VyronOpenAIResponsesLimits.requestBytes else { throw DevelopmentAgentError.contextBudget }
        return data
    }

    static func inputTokenCountRequest(
        model: String,
        input: [DevelopmentJSONValue],
        options: VyronOpenAIResponsesOptions
    ) throws -> Data {
        var body: [String: DevelopmentJSONValue] = ["model": .string(model), "input": .array(input)]
        if !options.tools.isEmpty { body["tools"] = .array(try options.tools.map(tool)) }
        if let name = options.forcedTool {
            body["tool_choice"] = .object(["type": .string("function"), "name": .string(name)])
        }
        if let effort = options.generation.reasoningEffort {
            body["reasoning"] = .object(["effort": .string(effort)])
        }
        let data = try JSONEncoder().encode(body)
        guard data.count <= VyronOpenAIResponsesLimits.requestBytes else { throw DevelopmentAgentError.contextBudget }
        return data
    }

    private static func budgetInput(_ input: [DevelopmentJSONValue]) -> [DevelopmentJSONValue] {
        input.map { item in
            guard case .object(var object) = item, case .array(let parts) = object["content"] else { return item }
            object["content"] = .array(
                parts.map { part in
                    guard case .object(var image) = part, image["type"] == .string("input_image") else { return part }
                    image["image_url"] = .string(
                        String(repeating: "x", count: VyronImageAttachment.estimatedContextTokens)
                    )
                    return .object(image)
                }
            )
            return .object(object)
        }
    }
}
