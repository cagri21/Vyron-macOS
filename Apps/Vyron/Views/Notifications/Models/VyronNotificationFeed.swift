import Foundation
import VyronCore

enum VyronNotificationFeed {
    static func build(
        conversations: [Conversation],
        runtime: VyronNotificationRuntime,
        readState: VyronNotificationReadState,
        calendarContext: VyronNotificationCalendarContext
    ) -> [VyronNotificationGroup] {
        var items: [VyronNotificationID: VyronNotificationItem] = [:]
        var workingResponses: Set<VyronNotificationResponseID> = []
        for conversation in conversations {
            for message in conversation.messages where message.conversationRole == .assistant {
                guard let activity = message.activity else { continue }
                let response = VyronNotificationResponseID(conversationID: conversation.id, responseID: message.id)
                let kind: VyronNotificationKind
                let date: Date
                switch activity.state {
                case .completed, .failed:
                    guard let finishedAt = activity.finishedAt else { continue }
                    kind = activity.state == .completed ? .completed : .failed
                    date = finishedAt
                case .working:
                    guard runtime.liveResponses.contains(response) else { continue }
                    workingResponses.insert(response)
                    kind = .working
                    date = activity.startedAt
                case .stopped:
                    continue
                }
                let id = VyronNotificationID(target: .response(response), kind: kind)
                items[id] = VyronNotificationItem(
                    id: id,
                    content: VyronNotificationContent(
                        title: conversation.title,
                        preview: String(message.content.trimmingCharacters(in: .whitespacesAndNewlines)
                            .prefix(VyronNotificationLimits.previewCharacters)),
                        projectPath: conversation.sidebarProjectPath
                    ),
                    date: date,
                    isRead: readState.isRead(id)
                )
            }
        }
        for attention in runtime.attention {
            switch attention.target {
            case .response(let response):
                guard workingResponses.contains(response) else { continue }
                let workingID = VyronNotificationID(target: attention.target, kind: .working)
                items.removeValue(forKey: workingID)
            case .scheduledRun:
                continue // Scheduler-only targets have persisted terminal events, not live permissions.
            case .plugins:
                break
            }
            let item = VyronNotificationItem(
                id: attention.id,
                content: attention.content,
                date: attention.date,
                isRead: readState.isRead(attention.id)
            )
            if items[item.id].map({ $0.date <= item.date }) ?? true { items[item.id] = item }
        }
        for scheduled in runtime.scheduledItems {
            guard case .scheduledRun = scheduled.id.target,
                scheduled.kind == .completed || scheduled.kind == .failed else { continue }
            items[scheduled.id] = VyronNotificationItem(
                id: scheduled.id, content: scheduled.content, date: scheduled.date,
                isRead: readState.isRead(scheduled.id)
            )
        }
        let ordered = items.values.sorted {
            if $0.date != $1.date { return $0.date > $1.date }
            return $0.id.sortKey < $1.id.sortKey
        }
        return VyronNotificationSection.allCases.compactMap { section in
            let matching = ordered.filter { sectionFor($0, context: calendarContext) == section }
            return matching.isEmpty ? nil : VyronNotificationGroup(id: section, items: matching)
        }
    }

    private static func sectionFor(
        _ item: VyronNotificationItem,
        context: VyronNotificationCalendarContext
    ) -> VyronNotificationSection {
        if item.isPriority { return .priority }
        if context.calendar.isDate(item.date, inSameDayAs: context.now) { return .today }
        if let yesterday = context.calendar.date(byAdding: .day, value: -1, to: context.now),
            context.calendar.isDate(item.date, inSameDayAs: yesterday) { return .yesterday }
        return .earlier
    }
}
