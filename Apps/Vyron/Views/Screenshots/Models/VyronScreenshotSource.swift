import Foundation

struct VyronScreenshotSource: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let target: VyronScreenshotTarget

    var kind: VyronScreenshotSourceKind {
        switch target {
        case .window: .window
        case .display: .display
        }
    }
}
