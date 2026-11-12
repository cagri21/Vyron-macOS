import VyronCore

enum VyronScheduledTaskLabels {
    static func recurrence(_ value: VyronTaskRecurrence) -> String {
        switch value {
        case .once: VyronScheduledTaskText.once
        case .daily: VyronScheduledTaskText.daily
        case .weekly: VyronScheduledTaskText.weekly
        }
    }

    static func mode(_ value: VyronScheduledTaskMode) -> String {
        switch value {
        case .agent: VyronScheduledTaskText.agent
        case .plan: VyronScheduledTaskText.plan
        case .chat: VyronScheduledTaskText.chat
        }
    }

    static func state(_ value: VyronScheduledTaskRunState) -> String {
        switch value {
        case .running: VyronScheduledTaskText.running
        case .completed: VyronScheduledTaskText.completedStatus
        case .failed: VyronScheduledTaskText.failedStatus
        case .stopped: VyronScheduledTaskText.stoppedStatus
        case .interrupted: VyronScheduledTaskText.interruptedStatus
        }
    }
}
