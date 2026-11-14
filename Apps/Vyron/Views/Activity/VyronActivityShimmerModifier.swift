import SwiftUI

struct VyronActivityShimmerModifier: ViewModifier {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if isActive, !reduceMotion {
                GeometryReader { geometry in
                    let bandWidth = geometry.size.width * VyronActivityMotionStyle.shimmerBandWidth
                    LinearGradient(
                        colors: [
                            palette.text.opacity(0),
                            palette.text.opacity(VyronActivityMotionStyle.shimmerHighlightOpacity),
                            palette.text.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth)
                    .phaseAnimator([false, true]) { highlight, hasCrossed in
                        highlight.offset(x: hasCrossed ? geometry.size.width : -bandWidth)
                    } animation: { hasCrossed in
                        .linear(duration: hasCrossed ? VyronActivityMotionStyle.shimmerDuration : 0)
                    }
                }
                .mask(content)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
    }
}
