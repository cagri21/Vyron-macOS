/// Optional internal capability; external providers retain the stable public ModelProvider contract.
package protocol VyronEffortChatProviding: ModelProvider {
    func chat(
        _ request: VyronChatInferenceRequest,
        onToken: @escaping @Sendable (String) -> Void
    ) async throws -> String
}
