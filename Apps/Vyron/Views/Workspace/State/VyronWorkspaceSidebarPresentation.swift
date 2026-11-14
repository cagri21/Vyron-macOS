struct VyronWorkspaceSidebarPresentation {
    private var prefersDocked = true
    private var showsOverlay = false

    func panelPresentation(isCompact: Bool) -> VyronWorkspacePanelPresentation {
        if isCompact { return showsOverlay ? .overlay : .hidden }
        return prefersDocked ? .docked : .hidden
    }

    mutating func toggle(isCompact: Bool) {
        if isCompact {
            showsOverlay.toggle()
        } else {
            prefersDocked.toggle()
        }
    }

    mutating func dismissOverlay() {
        showsOverlay = false
    }
}
