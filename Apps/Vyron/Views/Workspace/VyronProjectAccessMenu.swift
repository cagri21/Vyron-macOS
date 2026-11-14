import SwiftUI
import VyronCore

struct VyronProjectAccessMenu: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var showsApprovalChoices = false

    var body: some View {
        let _ = localizationLocale
        Button {
            showsApprovalChoices.toggle()
        } label: {
            HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
                Image(systemName: VyronProjectApprovalPresentation.symbol(model.interactions.projectApprovalMode))
                Text(VyronProjectApprovalPresentation.title(model.interactions.projectApprovalMode))
            }
            .font(VyronWorkspaceStyle.controlFont)
            .foregroundStyle(
                model.interactions.projectApprovalMode == .fullAccess ? palette.fullAccess : palette.muted
            )
            .padding(.horizontal, VyronWorkspaceStyle.approvalControlHorizontalPadding)
            .padding(.vertical, VyronWorkspaceStyle.approvalControlVerticalPadding)
            .background(showsApprovalChoices ? palette.field : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .disabled(!model.canChangeProjectApprovalMode)
        .help(VyronWorkspaceText.approvalQuestion)
        .accessibilityLabel(VyronProjectApprovalPresentation.title(model.interactions.projectApprovalMode))
        .popover(isPresented: $showsApprovalChoices, arrowEdge: .top) {
            VyronProjectAccessChoices { showsApprovalChoices = false }
        }
    }
}

