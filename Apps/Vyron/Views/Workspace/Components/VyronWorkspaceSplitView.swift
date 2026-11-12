import AppKit
import SwiftUI

struct VyronWorkspaceSplitView<Panel: View, Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var preferredPanelWidth: CGFloat
    @GestureState private var resizeStartWidth: CGFloat?
    @State private var isHoveringDivider = false

    let isPresented: Bool
    let configuration: VyronWorkspaceSplitConfiguration
    private let panel: Panel
    private let content: Content

    init(
        isPresented: Bool,
        configuration: VyronWorkspaceSplitConfiguration,
        @ViewBuilder panel: () -> Panel,
        @ViewBuilder content: () -> Content
    ) {
        self.isPresented = isPresented
        self.configuration = configuration
        self.panel = panel()
        self.content = content()
        _preferredPanelWidth = State(initialValue: configuration.idealPanelWidth)
    }

    var body: some View {
        GeometryReader { geometry in
            let panelWidth = configuration.panelWidth(preferred: preferredPanelWidth, available: geometry.size.width)
            HStack(spacing: 0) {
                if configuration.edge == .leading {
                    panelContainer(width: panelWidth, availableWidth: geometry.size.width)
                }
                content
                    .frame(minWidth: configuration.minimumContentWidth, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                if configuration.edge == .trailing {
                    panelContainer(width: panelWidth, availableWidth: geometry.size.width)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : VyronWorkspaceStyle.panelAnimation, value: isPresented)
            .animation(
                reduceMotion ? nil : VyronWorkspaceStyle.panelAnimation,
                value: configuration.minimumContentWidth
            )
        }
        .onChange(of: isPresented) { _, _ in restoreCursor() }
        .onDisappear { restoreCursor() }
    }

    private func panelContainer(width: CGFloat, availableWidth: CGFloat) -> some View {
        // Keep the panel at its full width while its container reveals or conceals it.
        // The trailing alignment sends the left panel out through the left edge.
        let alignment: Alignment = configuration.edge == .leading ? .trailing : .leading
        return ZStack(alignment: alignment) {
            if isPresented {
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
                .transition(.opacity)
            }
        }
        .frame(width: isPresented ? width + VyronWorkspaceStyle.dividerWidth : 0, alignment: alignment)
        .clipped()
        .allowsHitTesting(isPresented)
        .accessibilityHidden(!isPresented)
    }

    private func divider(width: CGFloat, availableWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Palette.border)
            .frame(width: VyronWorkspaceStyle.dividerWidth)
            .overlay {
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
    }

    private func restoreCursor() {
        guard isHoveringDivider else { return }
        NSCursor.pop()
        isHoveringDivider = false
    }
}
