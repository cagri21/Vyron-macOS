import SwiftUI
import VyronCore

struct VyronScheduledTaskCard: View {
    @Environment(\.locale) private var localizationLocale
    let task: VyronScheduledTask
    @ObservedObject var model: VyronScheduledTasksModel
    let actions: VyronScheduledTaskCardActions

    private var isActive: Bool { model.activeTaskID == task.id }
    private var consumedOneTime: Bool {
        task.schedule.recurrence == .once && task.progress.nextRunAt == nil
            && task.progress.lastRun != nil && !isActive
    }

    private var status: String {
        if consumedOneTime, let run = task.progress.lastRun {
            return VyronScheduledTaskLabels.state(run.state)
        }
        return task.progress.isEnabled ? VyronScheduledTaskText.ready : VyronScheduledTaskText.paused
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: VyronScheduledTaskStyle.rowSpacing) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: VyronScheduledTaskStyle.compactSpacing) {
                    Text(verbatim: task.definition.title).font(VyronScheduledTaskStyle.title)
                    Text(verbatim: task.definition.prompt)
                        .font(VyronScheduledTaskStyle.body).foregroundStyle(Palette.muted).lineLimit(3)
                }
                Spacer()
                if isActive {
                    ProgressView().controlSize(.small)
                } else {
                    Text(status)
                        .font(VyronScheduledTaskStyle.caption).foregroundStyle(Palette.muted)
                }
            }
            HStack(spacing: VyronScheduledTaskStyle.rowSpacing) {
                Text(VyronScheduledTaskLabels.recurrence(task.schedule.recurrence))
                Text(VyronScheduledTaskLabels.mode(task.definition.context.mode))
                Text(verbatim: task.schedule.timeZoneIdentifier)
            }.font(VyronScheduledTaskStyle.caption).foregroundStyle(Palette.muted)
            if let path = task.definition.context.workspacePath {
                Text(verbatim: path).font(VyronScheduledTaskStyle.caption).foregroundStyle(Palette.muted)
                    .lineLimit(1).truncationMode(.middle).help(path)
            }
            LabeledContent(VyronScheduledTaskText.nextRun) {
                if task.progress.isEnabled, let next = task.progress.nextRunAt {
                    Text(verbatim: formatted(next))
                } else {
                    Text(consumedOneTime || task.progress.isEnabled
                        ? VyronScheduledTaskText.noNextRun : VyronScheduledTaskText.paused)
                }
            }.font(VyronScheduledTaskStyle.caption).foregroundStyle(Palette.muted)
            if let run = task.progress.lastRun {
                LabeledContent(VyronScheduledTaskText.lastRun) {
                    Text(VyronScheduledTaskLabels.state(run.state))
                    Text(verbatim: formatted(run.output.startedAt))
                }.font(VyronScheduledTaskStyle.caption).foregroundStyle(Palette.muted)
                if let detail = run.output.detail, !detail.isEmpty {
                    Text(verbatim: detail).font(VyronScheduledTaskStyle.caption)
                        .foregroundStyle(run.state == .failed ? Palette.warning : Palette.muted)
                        .lineLimit(3).textSelection(.enabled)
                }
            }
            HStack(spacing: VyronScheduledTaskStyle.compactSpacing) {
                Button(VyronScheduledTaskText.edit, action: actions.edit).disabled(isActive)
                Button(VyronScheduledTaskText.remove, role: .destructive, action: actions.remove).disabled(isActive)
                if let id = task.progress.lastRun?.output.conversationID {
                    Button(VyronScheduledTaskText.openResult) { actions.openResult(id) }
                }
                Spacer()
                if isActive {
                    Button(VyronScheduledTaskText.stop) { model.stop() }
                } else {
                    if !consumedOneTime {
                        Button(task.progress.isEnabled ? VyronScheduledTaskText.pause : VyronScheduledTaskText.resume) {
                            model.setEnabled(!task.progress.isEnabled, for: task.id)
                        }
                    }
                    Button(VyronScheduledTaskText.runNow) { model.runNow(task.id) }
                        .disabled(model.activeTaskID != nil)
                }
            }.buttonStyle(QuietButtonStyle()).font(VyronScheduledTaskStyle.body)
        }
        .padding(VyronScheduledTaskStyle.cardPadding)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: VyronScheduledTaskStyle.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: VyronScheduledTaskStyle.cornerRadius).stroke(Palette.border))
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = localizationLocale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: task.schedule.timeZoneIdentifier)
        return formatter.string(from: date)
    }
}
