import AppKit
import SwiftUI

struct VyronWorkspaceTerminalSplitView<Panel: View, Content: View>: View {
    @State private var preferredPanelHeight = VyronWorkspaceStyle.terminalHeight
    @GestureState private var resizeStartHeight: CGFloat?
    @State private var isHoveringDivider = false

    let isPresented: Bool
    private let panel: Panel
    private let content: Content

    init(
        isPresented: Bool,
        @ViewBuilder panel: () -> Panel,
        @ViewBuilder content: () -> Content
    ) {
        self.isPresented = isPresented
        self.panel = panel()
        self.content = content()
    }

    var body: some View {
        GeometryReader { geometry in
            let panelHeight = VyronWorkspaceTerminalLayout.height(
                preferred: preferredPanelHeight,
                available: geometry.size.height
            )
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                if isPresented {
                    divider(height: panelHeight, availableHeight: geometry.size.height)
                        .zIndex(1)
                    panel
                        .frame(height: panelHeight)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: isPresented) { _, _ in restoreCursor() }
        .onDisappear { restoreCursor() }
    }

    private func divider(height: CGFloat, availableHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Palette.border)
            .frame(height: VyronWorkspaceStyle.dividerWidth)
            .overlay {
                Color.clear
                    .frame(height: VyronWorkspaceStyle.panelResizeTargetWidth)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering && !isHoveringDivider {
                            NSCursor.resizeUpDown.push()
                            isHoveringDivider = true
                        } else if !hovering {
                            restoreCursor()
                        }
                    }
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .updating($resizeStartHeight) { _, start, _ in
                            if start == nil { start = height }
                        }
                        .onChanged { value in
                            preferredPanelHeight = VyronWorkspaceTerminalLayout.resizedHeight(
                                start: resizeStartHeight ?? height,
                                translation: value.translation.height,
                                available: availableHeight
                            )
                        }
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(VyronAppText.inspectorTerminal)
            .accessibilityValue(Text(Int(height), format: .number))
            .accessibilityAdjustableAction { direction in
                let change: CGFloat
                switch direction {
                case .increment: change = VyronWorkspaceStyle.panelResizeAccessibilityStep
                case .decrement: change = -VyronWorkspaceStyle.panelResizeAccessibilityStep
                @unknown default: return
                }
                preferredPanelHeight = VyronWorkspaceTerminalLayout.height(
                    preferred: height + change,
                    available: availableHeight
                )
            }
    }

    private func restoreCursor() {
        guard isHoveringDivider else { return }
        NSCursor.pop()
        isHoveringDivider = false
    }
}
