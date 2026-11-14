import AppKit
import SwiftUI

struct VyronWorkspaceSplitView<Panel: View, Content: View>: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var preferredPanelWidth: CGFloat
    @GestureState private var resizeStartWidth: CGFloat?
    @State private var isHoveringDivider = false

    @Binding private var presentation: VyronWorkspacePanelPresentation
    let configuration: VyronWorkspaceSplitConfiguration
    private let panel: Panel
    private let content: Content

    init(
        presentation: Binding<VyronWorkspacePanelPresentation>,
        configuration: VyronWorkspaceSplitConfiguration,
        @ViewBuilder panel: () -> Panel,
        @ViewBuilder content: () -> Content
    ) {
        _presentation = presentation
        self.configuration = configuration
        self.panel = panel()
        self.content = content()
        _preferredPanelWidth = State(initialValue: configuration.idealPanelWidth)
    }

    var body: some View {
        GeometryReader { geometry in
            let available = geometry.size.width
            let isOverlay = presentation == .overlay
            let panelWidth = isOverlay
                ? configuration.overlayPanelWidth(preferred: preferredPanelWidth, available: available)
                : configuration.panelWidth(preferred: preferredPanelWidth, available: available)
            let dockedInset = presentation == .docked ? panelWidth + VyronWorkspaceStyle.dividerWidth : 0
            content
                .frame(minWidth: configuration.minimumContentWidth, maxWidth: .infinity, maxHeight: .infinity)
                .padding(configuration.edge == .leading ? .leading : .trailing, dockedInset)
                .disabled(isOverlay)
                .accessibilityHidden(isOverlay)
                .overlay {
                    if isOverlay {
                        palette.canvas.opacity(VyronWorkspaceStyle.sidebarOverlayScrimOpacity)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: dismissOverlay)
                            .accessibilityHidden(true)
                    }
                }
                .overlay(alignment: configuration.edge == .leading ? .leading : .trailing) {
                    panelContainer(width: panelWidth, availableWidth: available)
                }
                .animation(reduceMotion ? nil : VyronWorkspaceStyle.panelAnimation, value: presentation)
                .animation(
                    reduceMotion ? nil : VyronWorkspaceStyle.panelAnimation,
                    value: configuration.minimumContentWidth
                )
        }
        .onChange(of: presentation) { _, _ in restoreCursor() }
        .onDisappear { restoreCursor() }
    }

    private func panelContainer(width: CGFloat, availableWidth: CGFloat) -> some View {
        let alignment: Alignment = configuration.edge == .leading ? .trailing : .leading
        let isPresented = presentation != .hidden
        return ZStack(alignment: alignment) {
            // Keep the sidebar mounted so automatic collapse preserves project, search, and scroll state.
            if configuration.edge == .leading || isPresented {
                HStack(spacing: 0) {
                    if configuration.edge == .trailing {
                        divider(width: width, availableWidth: availableWidth)
                    }
                    panel
                        .frame(width: width)
                        .frame(maxHeight: .infinity)
                    if configuration.edge == .leading {
                        divider(width: width, availableWidth: availableWidth)
                    }
                }
                .frame(width: width + VyronWorkspaceStyle.dividerWidth)
            }
        }
        .frame(width: isPresented ? width + VyronWorkspaceStyle.dividerWidth : 0, alignment: alignment)
        .clipped()
        .opacity(isPresented ? 1 : 0)
        .disabled(!isPresented)
        .allowsHitTesting(isPresented)
        .accessibilityHidden(!isPresented)
    }

    private func divider(width: CGFloat, availableWidth: CGFloat) -> some View {
        Rectangle()
            .fill(palette.border)
            .frame(width: VyronWorkspaceStyle.dividerWidth)
            .overlay {
                if presentation == .docked {
                    resizeHandle(width: width, availableWidth: availableWidth)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                configuration.edge == .leading ? VyronSidebarText.projects : VyronSettingsText.inspector
            )
            .accessibilityValue(Text(Int(width), format: .number))
            .accessibilityAdjustableAction { direction in
                let change: CGFloat
                switch direction {
                case .increment: change = VyronWorkspaceStyle.panelResizeAccessibilityStep
                case .decrement: change = -VyronWorkspaceStyle.panelResizeAccessibilityStep
                @unknown default: return
                }
                preferredPanelWidth = configuration.panelWidth(preferred: width + change, available: availableWidth)
            }
            .accessibilityHidden(presentation != .docked)
    }

    private func resizeHandle(width: CGFloat, availableWidth: CGFloat) -> some View {
        Color.clear
            .frame(width: VyronWorkspaceStyle.panelResizeTargetWidth)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering && !isHoveringDivider {
                    NSCursor.resizeLeftRight.push()
                    isHoveringDivider = true
                } else if !hovering {
                    restoreCursor()
                }
            }
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .updating($resizeStartWidth) { _, start, _ in
                    if start == nil { start = width }
                }
                .onChanged { value in
                    let start = resizeStartWidth ?? width
                    let translation = layoutDirection == .leftToRight
                        ? value.translation.width : -value.translation.width
                    preferredPanelWidth = configuration.resizedPanelWidth(
                        start: start,
                        translation: translation,
                        available: availableWidth
                    )
                }
            )
            .frame(
                width: VyronWorkspaceStyle.dividerWidth,
                alignment: configuration.edge == .leading ? .trailing : .leading
            )
    }

    private func dismissOverlay() {
        if presentation == .overlay { presentation = .hidden }
    }

    private func restoreCursor() {
        guard isHoveringDivider else { return }
        NSCursor.pop()
        isHoveringDivider = false
    }
}
