import Foundation

/// Keeps the visible fill, thumb and pointer hit testing on the same bounded track.
struct VyronEffortSliderGeometry {
    let width: CGFloat
    let position: Double

    init(width: CGFloat, position: Double) {
        self.width = width.isFinite ? max(0, width) : 0
        let finitePosition = position.isFinite ? position : VyronEffortPresentation.position(for: .balanced)
        self.position = min(VyronEffortPresentation.maximumPosition, max(0, finitePosition))
    }

    var thumbDiameter: CGFloat { min(width, VyronEffortStyle.thumbDiameter) }
    var thumbLeading: CGFloat { travel * CGFloat(position / VyronEffortPresentation.maximumPosition) }
    var thumbCenter: CGFloat { thumbLeading + thumbDiameter / 2 }
    var fillWidth: CGFloat { min(width, max(0, thumbCenter)) }

    func position(at x: CGFloat) -> Double {
        guard travel > 0, x.isFinite else { return position }
        let fraction = Double((x - thumbDiameter / 2) / travel)
        return min(VyronEffortPresentation.maximumPosition, max(0, fraction * VyronEffortPresentation.maximumPosition))
    }

    private var travel: CGFloat { width - thumbDiameter }
}
