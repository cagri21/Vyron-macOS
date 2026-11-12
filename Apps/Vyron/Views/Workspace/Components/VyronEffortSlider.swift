import SwiftUI
import VyronCore

struct VyronEffortSlider: View {
    @Environment(\.locale) private var localizationLocale
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var model: AppModel
    @FocusState private var isFocused: Bool

    var body: some View {
        let _ = localizationLocale
        GeometryReader { geometry in
            let track = VyronEffortSliderGeometry(
                width: geometry.size.width,
                position: VyronEffortPresentation.position(for: model.composer.effort)
            )
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Palette.effortTrackInactive)
                    .frame(height: VyronEffortStyle.trackHeight)
                activeTrack
                    .frame(height: VyronEffortStyle.trackHeight)
                    .mask(alignment: .leading) { Rectangle().frame(width: track.fillWidth) }
                Circle()
                    .fill(Palette.effortSparkle)
                    .frame(width: track.thumbDiameter, height: track.thumbDiameter)
                    .offset(x: track.thumbLeading)
            }
            .frame(width: track.width, height: VyronEffortStyle.thumbDiameter, alignment: .leading)
            .animation(reduceMotion ? nil : VyronEffortStyle.selectionAnimation, value: model.composer.effort)
            .contentShape(Rectangle())
            .overlay {
                if isFocused {
                    Capsule().stroke(Palette.effortAccent, lineWidth: VyronEffortStyle.focusLineWidth)
                }
            }
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard canAdjust else { return }
                isFocused = true
                model.selectDevelopmentEffort(VyronEffortPresentation.manualEffort(
                    at: track.position(at: value.location.x)
                ))
            })
        }
        .frame(height: VyronEffortStyle.thumbDiameter)
        .opacity(canAdjust ? 1 : VyronEffortStyle.disabledOpacity)
        .focusable(canAdjust)
        .focused($isFocused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) {
            adjust(by: -1)
        }
        .onKeyPress(.rightArrow) {
            adjust(by: 1)
        }
        .onKeyPress(.downArrow) {
            adjust(by: -1)
        }
        .onKeyPress(.upArrow) {
            adjust(by: 1)
        }
        .onKeyPress(.home) {
            selectEndpoint(.quick)
        }
        .onKeyPress(.end) {
            selectEndpoint(.ultra)
        }
        .help(VyronEffortPresentation.description(model.composer.effort))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VyronWorkspaceText.effort)
        .accessibilityValue(VyronEffortPresentation.title(model.composer.effort))
        .accessibilityHint(VyronEffortPresentation.description(model.composer.effort))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: step(by: 1)
            case .decrement: step(by: -1)
            @unknown default: break
            }
        }
    }

    private var activeTrack: some View {
        Capsule()
            .fill(LinearGradient(
                colors: [Palette.effortTrackStart, Palette.effortTrackMiddle, Palette.effortTrackEnd],
                startPoint: .leading,
                endPoint: .trailing
            ))
            .overlay { sparkles }
            .clipShape(Capsule())
    }

    private var sparkles: some View {
        Canvas { context, size in
            for (index, point) in VyronEffortStyle.sparklePositions.enumerated() {
                let variation = index % 3
                let radius = VyronEffortStyle.sparkleRadius
                    + CGFloat(variation) * VyronEffortStyle.sparkleRadiusVariation
                let rect = CGRect(
                    x: point.x * size.width - radius,
                    y: point.y * size.height - radius,
                    width: radius * 2,
                    height: radius * 2
                )
                let opacity = VyronEffortStyle.sparkleOpacity
                    + Double(variation) * VyronEffortStyle.sparkleOpacityVariation
                context.fill(Path(ellipseIn: rect), with: .color(Palette.effortSparkle.opacity(opacity)))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var canAdjust: Bool { isEnabled && model.canSelectDevelopmentEffort }

    private func step(by offset: Int) {
        guard canAdjust else { return }
        model.selectDevelopmentEffort(VyronEffortPresentation.steppedEffort(from: model.composer.effort, by: offset))
    }

    private func adjust(by offset: Int) -> KeyPress.Result {
        guard canAdjust else { return .ignored }
        step(by: offset)
        return .handled
    }

    private func selectEndpoint(_ effort: AgentEffort) -> KeyPress.Result {
        guard canAdjust else { return .ignored }
        model.selectDevelopmentEffort(effort)
        return .handled
    }
}
