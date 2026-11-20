/// Mandatory context and requested work profile, before optional tool history is compacted.
package struct VyronDevelopmentBudgetRequest: Sendable {
    package let model: LocalModel
    package let configuration: VyronDevelopmentInferenceConfiguration
    package let minimumMessageBytes: Int

    package init(
        model: LocalModel,
        configuration: VyronDevelopmentInferenceConfiguration,
        minimumMessageBytes: Int
    ) {
        self.model = model
        self.configuration = configuration
        self.minimumMessageBytes = minimumMessageBytes
    }
}
