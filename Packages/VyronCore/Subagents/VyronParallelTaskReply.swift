import Foundation

struct VyronParallelTaskReply: Encodable {
    let task: Int
    let state: ResponseActivity.State
    let summary: String
    let truncated: Bool
}
