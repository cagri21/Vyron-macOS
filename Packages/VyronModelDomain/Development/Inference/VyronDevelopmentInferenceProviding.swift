/// Internal capability: public provider methods retain their existing error contracts.
package protocol VyronDevelopmentInferenceProviding: ModelProvider {
    func developmentInference(_ request: VyronDevelopmentInferenceRequest) async throws -> DevelopmentStep
}
