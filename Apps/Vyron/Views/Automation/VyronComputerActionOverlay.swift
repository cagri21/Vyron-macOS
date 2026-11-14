import AppKit
import SwiftUI

/// Click-through feedback for a native action that has already succeeded.
@MainActor
final class VyronComputerActionOverlay {
    // This badge also appears over other apps, separate from Vyron's windows.
    private let palette = VyronAppearancePalette.default
    private var panel: NSPanel?
    private var pointer: NSPanel?
    private var badge: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var owner: UUID?

    func show(title: String, targetFrame: CGRect?, owner: UUID? = nil) {
        clear()
        self.owner = owner
        showBadge(title)
        if let targetFrame { showTarget(targetFrame) }
        dismissal = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: VyronComputerPreviewStyle.overlayLifetime)
            } catch {
                return
            }
            self?.clear()
        }
    }

    private func showTarget(_ targetFrame: CGRect) {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let screens = NSScreen.screens.map(\.frame)
        guard let target = VyronComputerPointerGeometry.appKitFrame(for: targetFrame, primaryHeight: primaryHeight)
        else { return }
        let desktop = screens.reduce(CGRect.null) { $0.union($1) }
        let inset = VyronComputerPreviewStyle.highlightInset
        let frame = target.insetBy(dx: -inset, dy: -inset)
            .intersection(desktop)
        guard !frame.isNull, !frame.isEmpty else { return }
        let overlay = makePanel(frame: frame)
        overlay.contentView = NSHostingView(
            rootView: RoundedRectangle(cornerRadius: VyronComputerPreviewStyle.highlightRadius)
                .strokeBorder(palette.controlAccent, lineWidth: VyronComputerPreviewStyle.highlightWidth)
                .padding(VyronComputerPreviewStyle.highlightInset)
        )
        panel = overlay
        overlay.orderFrontRegardless()

        if let frame = VyronComputerPointerGeometry.desktopFrame(
            for: targetFrame, primaryHeight: primaryHeight, screens: screens
        ) {
            let overlay = makePanel(frame: frame)
            overlay.contentView = NSHostingView(rootView: VyronComputerPointer())
            pointer = overlay
            overlay.orderFrontRegardless()
        }
    }

    private func showBadge(_ title: String) {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = CGRect(
            x: screen.visibleFrame.maxX - VyronComputerPreviewStyle.badgeWidth
                - VyronComputerPreviewStyle.badgeScreenInset,
            y: screen.visibleFrame.maxY - VyronComputerPreviewStyle.badgeHeight
                - VyronComputerPreviewStyle.badgeScreenInset,
            width: VyronComputerPreviewStyle.badgeWidth,
            height: VyronComputerPreviewStyle.badgeHeight
        )
        let overlay = makePanel(frame: frame)
        overlay.contentView = NSHostingView(
            rootView: Label(title, systemImage: VyronSymbols.computerPreview)
                .font(VyronComputerPreviewStyle.title)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .padding(VyronComputerPreviewStyle.padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.canvas, in: RoundedRectangle(cornerRadius: VyronComputerPreviewStyle.radius))
                .overlay {
                    RoundedRectangle(cornerRadius: VyronComputerPreviewStyle.radius).stroke(palette.controlAccent)
                }
        )
        badge = overlay
        overlay.orderFrontRegardless()
    }

    private func makePanel(frame: CGRect) -> NSPanel {
        let overlay = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.isReleasedWhenClosed = false
        overlay.ignoresMouseEvents = true
        overlay.level = .floating
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return overlay
    }

    func clear() {
        owner = nil
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        pointer?.orderOut(nil)
        pointer?.close()
        pointer = nil
        badge?.orderOut(nil)
        badge?.close()
        badge = nil
    }

    func clear(owner: UUID) {
        if self.owner == owner { clear() }
    }
}
