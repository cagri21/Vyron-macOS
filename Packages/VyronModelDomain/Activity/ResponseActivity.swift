import Foundation

/// Observable work and explanations shared with the user for one response.
public struct ResponseActivity: Codable, Sendable, Equatable {
    public let startedAt: Date
    public private(set) var finishedAt: Date?
    public private(set) var state: State
    public private(set) var entries: [Entry]
    public private(set) var subagents: [VyronSubagentActivity]?

    public var subagentActivities: [VyronSubagentActivity] { subagents ?? [] }

    public var latestRecordedAt: Date {
        max(
            finishedAt ?? entries.last?.date ?? startedAt,
            subagentActivities.map { $0.activity.latestRecordedAt }.max() ?? startedAt
        )
    }

    public init(startedAt: Date = Date()) {
        self.startedAt = startedAt
        finishedAt = nil
        state = .working
        entries = []
        subagents = nil
    }

    public mutating func record(
        _ title: String,
        detail: String? = nil,
        kind: Entry.Kind = .status,
        at date: Date = Date()
    ) {
        record(VyronActivityContent(kind: kind, title: title, detail: detail), at: date)
    }

    public mutating func record(_ content: VyronActivityContent, at date: Date = Date()) {
        guard state == .working else { return }
        let trimmedTitle = content.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = String(trimmedTitle.prefix(VyronActivityLimits.maximumTitleCharacters))
        guard !title.isEmpty else { return }
        let trimmedDetail = content.detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = trimmedDetail.flatMap {
            $0.isEmpty ? nil : String($0.prefix(VyronActivityLimits.maximumDetailCharacters))
        }
        let bounded = VyronActivityContent(
            kind: content.kind,
            title: title,
            detail: detail,
            category: content.category
        )
        if entries.last?.content == bounded {
            return
        }
        entries.append(
            Entry(
                id: UUID(),
                date: max(date, entries.last?.date ?? startedAt),
                content: bounded
            )
        )
        if entries.count > VyronActivityLimits.maximumEntries {
            entries.removeFirst(entries.count - VyronActivityLimits.maximumEntries)
        }
    }

    public mutating func finish(_ state: State, at date: Date = Date()) {
        guard self.state == .working, state != .working else { return }
        if var children = subagents {
            for index in children.indices where children[index].activity.state == .working {
                children[index].finish(.stopped, summary: nil, at: date)
            }
            subagents = children
        }
        self.state = state
        finishedAt = max(date, latestRecordedAt)
    }

    public mutating func recordSubagent(
        _ event: VyronSubagentEvent,
        content: VyronActivityContent? = nil
    ) {
        guard state == .working else { return }
        var children = subagentActivities
        switch event.update {
        case .started:
            guard !children.contains(where: { $0.id == event.identity.id }),
                children.count < VyronActivityLimits.maximumSubagents
            else { return }
            children.append(VyronSubagentActivity(identity: event.identity, startedAt: event.date))
        case .activity(let update):
            guard let index = children.firstIndex(where: { $0.id == event.identity.id }),
                let content = content ?? update.activityContent
            else { return }
            children[index].record(content, at: event.date)
        case .finished(let completion):
            guard let index = children.firstIndex(where: { $0.id == event.identity.id }) else { return }
            children[index].finish(completion.state, summary: completion.summary, at: event.date)
        }
        subagents = children
    }

    public func elapsed(at date: Date = Date()) -> TimeInterval {
        max(0, (finishedAt ?? date).timeIntervalSince(startedAt))
    }
}
