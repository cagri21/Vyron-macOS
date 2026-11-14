import SwiftUI

struct VyronEffortUltraDrift: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                for index in 0..<VyronEffortStyle.ultraDriftCount {
                    let duration = 1.28 + 1.92 * variation(index, seed: 1)
                    let phase = time / duration + variation(index, seed: 2)
                    let x = (0.04 + 0.92 * variation(index, seed: 3)) * size.width + 4 * sin(phase * .pi)
                    let y = size.height / 2 + 7 * cos(phase * .pi)
                    let radius = VyronEffortStyle.ultraDriftRadius * (0.5 + 0.45 * variation(index, seed: 4))
                    let opacity = 0.4 + 0.6 * variation(index, seed: 5)
                    let bounds = CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius)
                    var particle = context
                    particle.addFilter(.shadow(
                        color: Palette.effortSparkle.opacity(VyronEffortStyle.ultraDriftGlowOpacity),
                        radius: VyronEffortStyle.ultraDriftGlowRadius
                    ))
                    particle.fill(Path(ellipseIn: bounds), with: .color(Palette.effortSparkle.opacity(opacity)))
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func variation(_ index: Int, seed: Int) -> Double {
        let value = sin(Double(index + 1) * 12.9898 + Double(seed) * 78.233) * 43_758.5453
        return value - floor(value)
    }
}
