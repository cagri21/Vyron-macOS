import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct VyronSidebarFolderDropTarget: ViewModifier {
    @Environment(\.vyronPalette) private var palette
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false
    @State private var dropID: UUID?
    @Binding private var projectPath: String?

    init(projectPath: Binding<String?>) {
        _projectPath = projectPath
    }

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                acceptDrop(providers)
            }
            .overlay {
                if isTargeted {
                    Rectangle()
                        .strokeBorder(palette.accent, lineWidth: VyronSidebarStyle.dropIndicatorSize)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard providers.count == 1, let provider = providers.first, !model.isShuttingDown else { return false }
        let id = UUID()
        dropID = id
        let activeProject = model.sidebarActiveProjectPath
        let activeChat = model.selectedConversationID
        // The provider must begin reading while the drop callback has access to the drag pasteboard.
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
            Task { @MainActor in
                guard dropID == id, !model.isShuttingDown, activeProject == model.sidebarActiveProjectPath,
                    activeChat == model.selectedConversationID else { return }

                if let data, let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL {
                    if let openedPath = model.openDroppedProjectFolder(at: url) { projectPath = openedPath }
                } else {
                    model.errorMessage = VyronStatusText.workspaceOpenFailure(
                        error?.localizedDescription ?? VyronStatusText.chooseWorkspaceHint
                    )
                }
            }
        }
        return true
    }
}
