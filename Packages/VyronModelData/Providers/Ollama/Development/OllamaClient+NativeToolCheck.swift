import Foundation
import VyronModelDomain

extension OllamaClient: VyronNativeToolChecking {
    public func requireNativeToolSupport(for model: LocalModel) async throws {
        try validateName(model.name)
        let selected = try await developmentModelWithCapabilities(model)
        guard ModelCatalog.codingIncompatibilityReason(for: selected) == nil else {
            throw ModelProviderError.unsupportedTools
        }
        // Shipped coding metadata retains its existing compatibility contract. Imported tags need a native call.
        if ModelCatalog.descriptor(for: selected.name)?.role == .coding { return }
        let installed = try await catalog(path: "tags")
        guard let current = installed.first(where: { Self.sameModelName($0.name, selected.name) }),
            configuredConnection || !current.isRemote
        else { throw ModelProviderError.unsupportedTools }
        // The actor owns one endpoint. A changed weight digest must obtain a fresh nonce proof.
        let proof = current.digest.map { selected.name + "@" + $0 }
        if let proof, verifiedNativeToolModels.contains(proof) { return }
        let details = try await modelMetadata(for: selected.name)
        guard details.capabilities?.contains("tools") == true else { throw ModelProviderError.unsupportedTools }
        let nonce = UUID().uuidString
        let tool = DevelopmentToolDefinition(function: .init(
            name: VyronOllamaNativeToolCheckPolicy.toolName,
            description: "Data-only native function transport check. This tool performs no action.",
            parameters: .init(
                properties: ["nonce": .init(type: "string", description: "Copy the supplied nonce exactly.")],
                required: ["nonce"]
            )
        ))
        let messages = [DevelopmentMessage(
            role: "user",
            content: "Call \(VyronOllamaNativeToolCheckPolicy.toolName) with nonce \(nonce). This is a data-only check. Do not print JSON."
        )]
        let thinking: VyronOllamaThinkingValue? = details.thinking?.values?.contains(.boolean(false)) == true
            ? .toggle(VyronOllamaThinkingToggle(false)) : nil
        let context = min(
            details.maximumContextTokens ?? VyronOllamaNativeToolCheckPolicy.contextTokens,
            settings.contextTokens ?? VyronOllamaNativeToolCheckPolicy.contextTokens,
            VyronOllamaNativeToolCheckPolicy.contextTokens
        )
        let output = min(
            settings.maxOutputTokens ?? VyronOllamaNativeToolCheckPolicy.maximumOutputTokens,
            max(
                VyronOllamaNativeToolCheckPolicy.minimumOutputTokens,
                context / VyronOllamaNativeToolCheckPolicy.outputContextDivisor
            ),
            VyronOllamaNativeToolCheckPolicy.maximumOutputTokens
        )
        var request = try makeRequest(path: "chat", body: DevelopmentStepRequest(
            model: selected.name,
            messages: messages.map { VyronOllamaDevelopmentMessage(message: $0) },
            think: thinking,
            tools: [tool],
            options: .init(num_ctx: context, num_predict: output)
        ))
        request.timeoutInterval = VyronOllamaNativeToolCheckPolicy.timeoutSeconds
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else { throw httpError(http.statusCode, data: data) }
        guard data.count <= VyronOllamaNativeToolCheckPolicy.maximumResponseBytes else {
            throw ModelProviderError.unsupportedTools
        }
        let reply = try JSONDecoder().decode(DevelopmentStepResponse.self, from: data)
        if let error = reply.error { throw serverError(error) }
        guard reply.done == true, reply.message?.role == "assistant", let calls = reply.message?.toolCalls, calls.count == 1,
            calls[0].function.name == VyronOllamaNativeToolCheckPolicy.toolName,
            calls[0].function.arguments == ["nonce": .string(nonce)]
        else { throw ModelProviderError.unsupportedTools }
        if verifiedNativeToolModels.count >= VyronOllamaNativeToolCheckPolicy.maximumCachedProofs {
            verifiedNativeToolModels.removeAll()
        }
        if let proof { verifiedNativeToolModels.insert(proof) }
    }
}
