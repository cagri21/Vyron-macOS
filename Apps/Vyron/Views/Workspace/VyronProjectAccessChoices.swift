import SwiftUI
import VyronCore

struct VyronProjectAccessChoices: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    private let dismiss: () -> Void

    init(dismiss: @escaping () -> Void = {}) {
        self.dismiss = dismiss
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
            Text(VyronWorkspaceText.approvalQuestion)
                .font(VyronWorkspaceStyle.controlFont)
                .foregroundStyle(palette.muted)
                .padding(.horizontal, VyronWorkspaceStyle.approvalRowPadding)
            ForEach(
                [VyronProjectApprovalMode.askForApproval, .approveForMe, .fullAccess],
                id: \.self
            ) { mode in
                approvalRow(mode)
            }
            Divider()
            scope
        }
        .padding(VyronWorkspaceStyle.approvalPopoverPadding)
        .frame(width: VyronWorkspaceStyle.approvalPopoverWidth)
        .background(palette.field)
    }

    private var scope: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
            Text(VyronWorkspaceText.approvalScope)
            if let workspaceURL = model.workspaceState.workspaceURL {
                Text(verbatim: workspaceURL.path)
                    .textSelection(.enabled)
            } else {
                Text(VyronWorkspaceText.projectRequired)
            }
            if model.composer.mode == .plan {
                Text(VyronWorkspaceText.planningApprovalScope)
            }
        }
        .font(VyronWorkspaceStyle.captionFont)
        .foregroundStyle(palette.muted)
        .padding(.horizontal, VyronWorkspaceStyle.approvalRowPadding)
    }

    private func approvalRow(_ mode: VyronProjectApprovalMode) -> some View {
        let selected = model.interactions.projectApprovalMode == mode
        let isActiveFullAccess = selected && mode == .fullAccess
        return Button {
            model.selectProjectApprovalMode(mode)
            dismiss()
        } label: {
            HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
                Image(systemName: VyronProjectApprovalPresentation.symbol(mode))
                    .frame(width: VyronWorkspaceStyle.approvalIconWidth)
                VStack(alignment: .leading, spacing: VyronWorkspaceStyle.approvalRowSpacing) {
                    Text(VyronProjectApprovalPresentation.title(mode))
                        .font(VyronWorkspaceStyle.controlFont)
                    Text(VyronProjectApprovalPresentation.description(mode))
                        .font(VyronWorkspaceStyle.captionFont)
                        .foregroundStyle(isActiveFullAccess ? palette.fullAccess : palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: VyronWorkspaceStyle.compactSpacing)
                Image(systemName: VyronSymbols.check)
                    .opacity(selected ? 1 : 0)
            }
            .foregroundStyle(isActiveFullAccess ? palette.fullAccess : palette.text)
            .padding(VyronWorkspaceStyle.approvalRowPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.canChangeProjectApprovalMode)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
