import Foundation
import VyronCore

struct VyronActivityPresentation: Equatable, Sendable {
    let blocks: [VyronActivityBlock]
    let currentStatus: ResponseActivity.Entry?
    let isVisible: Bool
    let showsDetailsLink: Bool

    init(activity: ResponseActivity, response: String, isStreaming: Bool) {
        let duplicateID = Self.finalExplanationID(activity: activity, response: response)
        var blocks: [VyronActivityBlock] = []
        var pendingTools: [ResponseActivity.Entry] = []

        for entry in activity.entries {
            switch entry.kind {
            case .status:
                continue
            case .tool:
                pendingTools.append(entry)
            case .explanation:
                guard entry.id != duplicateID else { continue }
                if let first = pendingTools.first {
                    blocks.append(.tools(VyronActivityToolGroup(id: first.id, entries: pendingTools)))
                    pendingTools.removeAll(keepingCapacity: true)
                }
                let detail = entry.detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                blocks.append(
                    .explanation(VyronActivityExplanation(id: entry.id, text: detail.isEmpty ? entry.title : detail))
                )
            }
        }
        if let first = pendingTools.first {
            blocks.append(.tools(VyronActivityToolGroup(id: first.id, entries: pendingTools)))
        }
        self.blocks = blocks

        let showsStatus = (isStreaming && activity.state == .working)
            || activity.state == .stopped || activity.state == .failed
        currentStatus = showsStatus && activity.entries.last?.kind == .status ? activity.entries.last : nil
        isVisible = !blocks.isEmpty || currentStatus != nil || !activity.subagentActivities.isEmpty
            || (isStreaming && activity.state == .working) || activity.finishedAt != nil
        showsDetailsLink = !isStreaming && activity.state != .working
            && (activity.entries.contains { $0.kind == .tool } || !activity.subagentActivities.isEmpty)
    }

    private static func finalExplanationID(activity: ResponseActivity, response: String) -> UUID? {
        guard activity.state == .completed,
            let explanation = activity.entries.last(where: { $0.kind == .explanation }),
            let detail = explanation.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
            !detail.isEmpty
        else { return nil }

        // Activity detail can be a truncated prefix of the returned summary.
        let response = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return response.hasPrefix(detail) ? explanation.id : nil
    }
}
