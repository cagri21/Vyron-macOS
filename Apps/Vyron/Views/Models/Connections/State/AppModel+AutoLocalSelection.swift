extension AppModel {
    func useAutoLocalModels() {
        guard canManageModelSelection, modelSelection.isBuiltinConnection else { return }
        do {
            try modelSelection.useAutoLocalSelection()
            errorMessage = nil
            statusMessage = VyronWorkspaceText.autoLocalEnabled
            requestModelFeatureVerification()
        } catch {
            statusMessage = error.localizedDescription
            errorMessage = error.localizedDescription
        }
    }
}
