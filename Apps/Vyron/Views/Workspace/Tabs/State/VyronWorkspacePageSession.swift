import Combine
import Foundation

@MainActor
final class VyronWorkspacePageSession: ObservableObject {
    @Published var draft: VyronWorkspacePage
    @Published private(set) var isSaved: Bool
    private var saved: VyronWorkspacePage

    init(page: VyronWorkspacePage, isSaved: Bool = false) {
        draft = page
        saved = page
        self.isSaved = isSaved
    }

    var hasChanges: Bool { draft.title != saved.title || draft.body != saved.body }

    func didSave(_ page: VyronWorkspacePage) {
        draft = page
        saved = page
        isSaved = true
    }
}
