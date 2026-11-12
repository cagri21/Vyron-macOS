import Combine

@MainActor
final class VyronChatHandoffState: ObservableObject {
    @Published var selection: VyronChatHandoffSelection
    @Published var request: String
    @Published var isSaving = false
    @Published var error: String?

    init(presentation: VyronChatHandoffPresentation) {
        selection = presentation.destination ?? VyronChatHandoffSelection(projectPath: "", workspacePath: "")
        request = presentation.initialRequest ?? ""
    }
}
