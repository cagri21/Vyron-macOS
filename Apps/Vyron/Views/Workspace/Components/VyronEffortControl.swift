import SwiftUI

struct VyronEffortControl: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var showsEffort = false

    var body: some View {
        let _ = localizationLocale
        Button {
            showsEffort.toggle()
        } label: {
            VyronInferenceSelectionLabel(
                modelName: selectedModelLabel, effort: model.composer.effort,
                speed: model.responseSpeed, expanded: showsEffort
            )
        }
        .buttonStyle(.plain)
        .help(selectionDescription)
        .accessibilityLabel(VyronWorkspaceText.inferenceSettings)
        .accessibilityValue(selectionSummary)
        .accessibilityHint(VyronEffortPresentation.description(model.composer.effort))
        .popover(isPresented: $showsEffort, arrowEdge: .bottom) {
            VyronEffortPopover()
        }
    }

    private var selectedModelLabel: String {
        VyronInferenceSelectionPresentation.modelName(
            model.modelSelection.selectedModel, automatic: model.modelSelection.automaticModelSelection
        )
    }

    private var selectionDescription: String {
        selectionSummary + "\n" + VyronEffortPresentation.description(model.composer.effort)
    }

    private var selectionSummary: String {
        VyronInferenceSelectionPresentation.summary(
            model: selectedModelLabel, effort: model.composer.effort, speed: model.responseSpeed
        )
    }
}
