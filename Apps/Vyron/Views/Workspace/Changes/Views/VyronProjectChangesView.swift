import AppKit
import SwiftUI
import VyronDevelopment

struct VyronProjectChangesView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var viewMode = VyronInspectorDiffMode.diff
    @State private var filter = ""

    var body: some View {
        let _ = localizationLocale
        let inspector = model.inspector
        VStack(spacing: 0) {
            if let review = inspector.responseChangeReview {
                if model.workspaceState.workspaceURL != nil && !model.isChatWorkspace {
                    Picker(
                        VyronAppText.inspectorView,
                        selection: Binding(
                            get: { inspector.showsResponseChanges },
                            set: { inspector.showsResponseChanges = $0 }
                        )
                    ) {
                        Text(VyronAppText.inspectorProjectChanges).tag(false)
                        Text(VyronAppText.inspectorResponseChanges).tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .help(review.workspacePath)
                    .padding(VyronWorkspaceStyle.controlSpacing)
                } else {
                    Text(VyronAppText.inspectorResponseChanges)
                        .font(VyronWorkspaceStyle.controlFont)
                        .foregroundStyle(palette.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(review.workspacePath)
                        .padding(VyronWorkspaceStyle.controlSpacing)
                }
            }
            if let change = inspector.selectedReviewChange {
                reviewLayout(change: change)
            } else {
                missingChanges
            }
        }
        .onChange(of: inspector.showsResponseChanges) { _, _ in
            viewMode = .diff
            filter = ""
        }
        .background(palette.canvas)
    }

    private func reviewLayout(change: DevelopmentChange) -> some View {
        GeometryReader { geometry in
            if geometry.size.width >= VyronChangesStyle.sideBySideMinimumWidth {
                HStack(spacing: 0) {
                    details(change)
                    border.frame(width: VyronWorkspaceStyle.dividerWidth)
                    fileList(selectedPath: change.path)
                        .frame(width: VyronChangesStyle.listWidth)
                }
            } else {
                VStack(spacing: 0) {
                    fileList(selectedPath: change.path)
                        .frame(height: listHeight)
                    border.frame(height: VyronWorkspaceStyle.dividerWidth)
                    details(change)
                }
            }
        }
    }

    private var listHeight: CGFloat {
        let contentHeight = CGFloat(model.inspector.reviewChanges.count + 2) * VyronChangesStyle.rowHeight
        return min(VyronChangesStyle.listMaximumHeight, contentHeight)
    }

    private func fileList(selectedPath: String) -> some View {
        VyronInspectorChangedFilesList(
            changes: model.inspector.reviewChanges,
            selectedPath: selectedPath,
            filter: $filter,
            selectPath: { path in
                model.inspector.selectChangeReviewPath(path)
                viewMode = .diff
            }
        )
    }

    private func details(_ change: DevelopmentChange) -> some View {
        VyronInspectorChangeDetail(
            change: change,
            viewMode: $viewMode,
            revertState: revertState,
            revert: { model.revertChange(change.path) }
        )
        .onChange(of: VyronDiffRevision(change)) { _, _ in viewMode = .diff }
    }

    private var revertState: VyronInspectorRevertState {
        if model.inspector.showsResponseChanges { return .hidden }
        if model.foregroundRun.isGenerating || model.foregroundRun.developmentResponse != nil
            || model.foregroundRun.isStoppingDevelopment || model.scheduledTasks.activeTaskID != nil {
            return .disabled
        }
        return .enabled
    }

    private var missingChanges: some View {
        VStack(spacing: VyronWorkspaceStyle.controlSpacing) {
            Image(systemName: VyronSymbols.changes)
                .font(VyronWorkspaceStyle.heading)
                .foregroundStyle(palette.muted)
            Text(VyronAppText.inspectorNoChanges)
                .font(VyronWorkspaceStyle.controlFont.weight(.medium))
            Text(VyronAppText.inspectorCompletedEditsHint)
                .font(VyronWorkspaceStyle.captionFont)
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
        }
        .padding(VyronWorkspaceStyle.outerPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var border: some View {
        Rectangle().fill(palette.border)
    }
}
