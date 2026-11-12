import Foundation

enum VyronNotificationTarget: Codable, Hashable, Sendable {
    case response(VyronNotificationResponseID)
    case scheduledRun(VyronNotificationScheduledRunID)
    case plugins

    var conversationID: UUID? {
        if case .response(let response) = self { return response.conversationID }
        return nil
    }

    var responseID: UUID? {
        if case .response(let response) = self { return response.responseID }
        return nil
    }

    var sortKey: String {
        switch self {
        case .response(let response):
            return "response-" + response.conversationID.uuidString + response.responseID.uuidString
        case .scheduledRun(let run): return "scheduled-" + run.taskID.uuidString + run.runID.uuidString
        case .plugins: return "plugins"
        }
    }
}
