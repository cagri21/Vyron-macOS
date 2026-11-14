import AppKit
import SwiftUI
import VyronDevelopment

struct VyronInspectorChangeDetail: View {
    let change: DevelopmentChange
    @Binding var viewMode: VyronInspectorDiffMode
    let revertState: VyronInspectorRevertState
    let revert: () -> Void

    @State private var diff: VyronUnifiedDiff?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: VyronWorkspaceStyle.dividerWidth)
            preview
                .id(change.path)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: VyronDiffRevision(change)) {
            diff = nil
            let change = change
            let result = await Task.detached { VyronUnifiedDiff(change: change) }.value
            if !Task.isCancelled { diff = result }
        }
    }

    private var header: some View {
        VStack(spacing: VyronWorkspaceStyle.compactSpacing) {
            HStack(spacing: VyronWorkspaceStyle.compactSpacing) {
                Text(verbatim: change.path)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(change.path)
                Spacer(minLength: 0)
                if let diff {
                    VyronDiffCountsView(added: diff.addedCount, removed: diff.removedCount)
                }
                copyDiff
                if revertState != .hidden {
                    Button(VyronAppText.inspectorRevert, action: revert)
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.warning)
                        .disabled(revertState == .disabled)
                        .help(VyronAppText.inspectorChangesHint)
                }
            }
            Picker(VyronAppText.inspectorView, selection: $viewMode) {
                ForEach(VyronInspectorDiffMode.allCases, id: \.self) { mode in
                    Text(verbatim: mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
        }
        .font(VyronWorkspaceStyle.controlFont)
        .padding(VyronWorkspaceStyle.controlSpacing)
        .background(Palette.surface)
    }

    private var copyDiff: some View {
        Button {
            guard let diff else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(diff.unifiedText, forType: .string)
        } label: {
            Image(systemName: VyronSymbols.copy)
                .foregroundStyle(Palette.muted)
        }
        .buttonStyle(.plain)
        .disabled(diff == nil)
        .help(VyronAppText.inspectorCopyDiff)
        .accessibilityLabel(VyronAppText.inspectorCopyDiff)
    }

    @ViewBuilder
    private var preview: some View {
        if viewMode == .diff {
            if let diff {
                VyronUnifiedDiffView(diff: diff)
            }
        } else {
            ScrollView([.horizontal, .vertical]) {
                Text(verbatim: viewMode == .before
                    ? (change.before ?? VyronAppText.inspectorFileDidNotExist) : change.after)
                    .font(VyronChangesStyle.codeFont)
                    .foregroundStyle(Palette.codeText)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(VyronWorkspaceStyle.controlSpacing)
            }
        }
    }
}
