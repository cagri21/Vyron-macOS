import SwiftUI

struct VyronEffortUltraBurst: View {
    let isUltra: Bool

    var body: some View {
        Color.clear
            .frame(width: VyronEffortStyle.ultraBurstSize, height: VyronEffortStyle.ultraBurstSize)
            .keyframeAnimator(initialValue: 1.0, trigger: isUltra) { view, progress in
                view.overlay {
                    if isUltra && progress < 1 {
                        particles(progress: progress)
                    }
                }
            } keyframes: { _ in
                MoveKeyframe(0)
                LinearKeyframe(1, duration: VyronEffortStyle.ultraBurstDuration)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private nonisolated func particles(progress: Double) -> some View {
        Canvas { context, size in
            for index in 0..<VyronEffortStyle.ultraBurstCount {
                let phase = max(0, (progress - Double(index % 4) * 0.007) / 0.979)
                let travel = 1 - pow(1 - min(phase, 1), 3)
                let rise = min(phase / 0.22, 1)
                let fade = max(0, (phase - 0.22) / 0.78)
                let radius = VyronEffortStyle.ultraBurstRadius * (0.25 + 1.03 * rise - 0.73 * fade)
                let angle = Double(index) * 2 * .pi / Double(VyronEffortStyle.ultraBurstCount)
                let distance = VyronEffortStyle.ultraBurstDistance * (0.65 + 0.07 * Double(index % 6)) * travel
                let x = size.width / 2 + cos(angle) * distance
                let y = size.height / 2 + sin(angle) * distance
                let bounds = CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)
                let color = index.isMultiple(of: 4) ? Palette.effortTrackMiddle : Palette.effortTrackEnd
                context.fill(Path(ellipseIn: bounds), with: .color(color.opacity(rise * (1 - fade))))
            }
        }
    }
}
