import Foundation
import SwiftUI
import VyronDevelopment

struct VyronInspectorChangedFilesList: View {
    let changes: [DevelopmentChange]
    let selectedPath: String
    @Binding var filter: String
    let selectPath: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VyronWorkspaceStyle.compactSpacing) {
            HStack {
                Text(VyronStatusText.changedFilesHeading)
                    .foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Text(changes.count, format: .number)
                    .foregroundStyle(Palette.muted)
                    .monospacedDigit()
            }
            .padding(.horizontal, VyronWorkspaceStyle.controlSpacing)

            if changes.count > 1 {
                TextField(VyronAppText.inspectorFindFile, text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, VyronWorkspaceStyle.controlSpacing)
            }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredChanges) { change in
                        VyronInspectorChangeFileRow(change: change, isSelected: change.path == selectedPath) {
                            selectPath(change.path)
                        }
                    }
                }
            }
        }
        .font(VyronWorkspaceStyle.controlFont)
        .padding(.top, VyronWorkspaceStyle.compactSpacing)
        .background(Palette.canvas)
    }

    private var filteredChanges: [DevelopmentChange] {
        if filter.isEmpty { return changes }
        return changes.filter { $0.path.localizedCaseInsensitiveContains(filter) }
    }
}
