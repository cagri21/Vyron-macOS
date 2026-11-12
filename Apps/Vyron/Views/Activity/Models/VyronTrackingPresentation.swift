import Foundation
import VyronCore

struct VyronTrackingPresentation {
    let activity: ResponseActivity
    let isLive: Bool

    var inlinePhase: String {
        activity.entries.last?.category == .question && activity.state == .working
            ? VyronQuestionText.waitingForAnswer : VyronTrackingText.thinking
    }

    var phase: String {
        guard activity.state == .working else { return Self.status(activity.state) }
        guard let entry = activity.entries.last else { return VyronTrackingText.thinking }
        if entry.category == .question { return VyronQuestionText.waitingForAnswer }
        return entry.kind == .tool ? entry.title : VyronTrackingText.thinking
    }

    func elapsedTitle(at date: Date) -> String {
        let live = isLive && activity.state == .working
        let measuredAt = live ? date : activity.finishedAt ?? activity.latestRecordedAt
        let duration = Self.duration(activity.elapsed(at: measuredAt))
        return live
            ? VyronTrackingText.workingFor(duration) : VyronTrackingText.workedFor(duration)
    }

    static func duration(_ interval: TimeInterval) -> String {
        let seconds = interval.isFinite ? Int(min(359_999, max(0, interval))) : 0
        if seconds >= 60, seconds.isMultiple(of: 60) {
            return VyronTrackingText.durationMinutes(seconds / 60)
        }
        return seconds < 60
            ? VyronAppText.activitySeconds(seconds)
            : VyronAppText.activityMinutesSeconds(seconds / 60, seconds % 60)
    }

    static func status(_ state: ResponseActivity.State) -> String {
        switch state {
        case .working: VyronTrackingText.running
        case .completed: VyronTrackingText.completed
        case .stopped: VyronTrackingText.stopped
        case .failed: VyronTrackingText.failed
        }
    }

    static func symbol(_ entry: ResponseActivity.Entry) -> String {
        switch entry.category ?? .general {
        case .files: VyronSymbols.folder
        case .read: VyronSymbols.files
        case .search: VyronSymbols.search
        case .edit: VyronSymbols.pencil
        case .command: VyronSymbols.terminal
        case .integration: VyronSymbols.plugins
        case .question: VyronSymbols.chat
        case .agents: VyronSymbols.subagents
        case .general: entry.kind == .explanation ? VyronSymbols.chat : VyronSymbols.activityTools
        }
    }

    static func stateSymbol(_ state: ResponseActivity.State) -> String {
        switch state {
        case .working: VyronSymbols.activityWorking
        case .completed: VyronSymbols.checkmark
        case .stopped: VyronSymbols.activityStopped
        case .failed: VyronSymbols.warning
        }
    }
}
