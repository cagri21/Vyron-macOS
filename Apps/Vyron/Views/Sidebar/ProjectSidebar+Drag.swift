import SwiftUI
import VyronCore

extension ProjectSidebar {
    func sidebarDragGesture(_ entries: [VyronSidebarEntry]) -> some Gesture {
        DragGesture(
            minimumDistance: VyronSidebarStyle.dragMinimumDistance,
            coordinateSpace: .named(VyronSidebarStyle.dragCoordinateSpace)
        )
        .updating($isSidebarDragging) { _, dragging, _ in dragging = true }
        .onChanged { drag in
            if draggedRow == nil {
                draggedRow = entries.first { entry in
                    entry.row != nil && sidebarDropFrames[entry.id]?.contains(drag.startLocation) == true
                }?.row
            }
            let target = draggedRow.flatMap { dropTarget(for: $0, at: drag.location, entries: entries) }
            if sidebarDropTarget != target { sidebarDropTarget = target }
        }
        .onEnded { drag in
            defer { clearSidebarDrag() }
            guard let draggedRow,
                let target = dropTarget(for: draggedRow, at: drag.location, entries: entries),
                model.moveSidebarRow(draggedRow, to: target.destination)
            else { return }
            showMovedChat(draggedRow, in: target.destination.group)
        }
    }

    func clearSidebarDrag() {
        draggedRow = nil
        sidebarDropTarget = nil
    }

    func sidebarDropSurface<Content: View>(
        _ surface: VyronSidebarDropSurface,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .overlay { dropIndicator(for: surface).allowsHitTesting(false).accessibilityHidden(true) }
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .named(VyronSidebarStyle.dragCoordinateSpace))
            } action: { frame in
                sidebarDropFrames[surface.id] = frame
            }
            .onDisappear { sidebarDropFrames.removeValue(forKey: surface.id) }
    }

    private func dropTarget(
        for row: VyronSidebarRow,
        at location: CGPoint,
        entries: [VyronSidebarEntry]
    ) -> VyronSidebarDropTarget? {
        guard CGRect(origin: .zero, size: sidebarViewportSize).contains(location) else { return nil }
        let surface = entries.first { containsDropPoint(location, in: sidebarDropFrames[$0.id]) }
            .map(VyronSidebarDropSurface.entry) ?? .topLevel
        guard let frame = sidebarDropFrames[surface.id], containsDropPoint(location, in: frame),
            let destination = surface.destination(for: row, verticalPosition: (location.y - frame.minY) / frame.height),
            model.canMoveSidebarRow(row, to: destination)
        else { return nil }
        return VyronSidebarDropTarget(surfaceID: surface.id, destination: destination)
    }

    private func containsDropPoint(_ location: CGPoint, in frame: CGRect?) -> Bool {
        guard let frame, frame.height > 0 else { return false }
        return frame.insetBy(dx: 0, dy: -VyronSidebarStyle.rowSpacing / 2).contains(location)
    }

    @ViewBuilder
    private func dropIndicator(for surface: VyronSidebarDropSurface) -> some View {
        if let sidebarDropTarget, sidebarDropTarget.surfaceID == surface.id {
            switch sidebarDropTarget.destination.position {
            case .before:
                insertionLine.frame(maxHeight: .infinity, alignment: .top)
            case .after:
                insertionLine.frame(maxHeight: .infinity, alignment: .bottom)
            case .end:
                if case .topLevel = surface {
                    VStack(spacing: VyronSidebarStyle.rowSpacing) {
                        insertionLine
                        Text(VyronSidebarText.topLevel)
                            .font(VyronSidebarStyle.detailFont)
                            .foregroundStyle(palette.text)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                } else {
                    RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius)
                        .strokeBorder(palette.accent, lineWidth: VyronSidebarStyle.dropIndicatorSize)
                }
            }
        }
    }

    private var insertionLine: some View {
        Capsule().fill(palette.accent).frame(height: VyronSidebarStyle.dropIndicatorSize)
    }
}
