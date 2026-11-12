import Foundation
import VyronCore

struct VyronQueueTestRequest: Sendable {
    let continuation: CheckedContinuation<String, any Error>
    let onToken: @Sendable (String) -> Void
}
