import SwiftUI
import VyronModelData
import VyronModelDomain

struct VyronChangeModelPrecisionButton: View {
    @EnvironmentObject private var model: AppModel
    let installed: LocalModel
    let onOpen: (LocalModel) -> Void

    var body: some View {
        if ModelSourceClient.canDiscoverPrecisionVariants(for: installed)
            || !ModelSourceClient.installedPrecisionVariants(for: installed, among: model.modelSelection.models).isEmpty {
            Button(VyronAppText.settingsChangePrecision) { onOpen(installed) }
                .font(VyronWorkspaceStyle.captionFont)
                .buttonStyle(QuietButtonStyle())
                .disabled(!model.canChangeLocalModelPrecision)
        }
    }
}
