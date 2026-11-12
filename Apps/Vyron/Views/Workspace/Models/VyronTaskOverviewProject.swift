import Foundation
import VyronDevelopment

struct VyronTaskOverviewProject: Sendable {
    let path: String?
    let changes: [DevelopmentChange]

    var name: String? { path.map { URL(fileURLWithPath: $0).lastPathComponent } }
    var outputs: [DevelopmentChange] { changes.filter { $0.before == nil } }
}
