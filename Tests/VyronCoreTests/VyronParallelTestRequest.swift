import Foundation
@testable import VyronCore

struct VyronParallelTestRequest: Sendable {
    let model: String
    let mode: DevelopmentMode
    let messages: [DevelopmentMessage]
    let tools: [String]
}
