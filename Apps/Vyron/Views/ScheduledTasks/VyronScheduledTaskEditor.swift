import SwiftUI
import VyronCore
import VyronModelDomain

struct VyronScheduledTaskEditor: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    let initial: VyronScheduledTask?
    let context: VyronScheduledTaskContext
    let save: (VyronScheduledTask) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var task: VyronScheduledTask
    @State private var error: String?
    private static let initialScheduleDelay: TimeInterval = 5 * 60

    init(
        initial: VyronScheduledTask?,
        context: VyronScheduledTaskContext,
        save: @escaping (VyronScheduledTask) -> Bool,
        template: VyronScheduledTaskDefinition? = nil
    ) {
        self.initial = initial
        self.context = context
        self.save = save
        let firstRun = Date().addingTimeInterval(Self.initialScheduleDelay)
        _task = State(initialValue: initial ?? VyronScheduledTask(
            id: UUID(),
            definition: template ?? VyronScheduledTaskDefinition(title: "", prompt: "", context: context),
            schedule: VyronTaskSchedule(
                startsAt: firstRun,
                recurrence: .once,
                timeZoneIdentifier: TimeZone.current.identifier
            ),
            progress: VyronScheduledTaskProgress(isEnabled: true, nextRunAt: firstRun, lastRun: nil)
        ))
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 0) {
            Text(initial == nil ? VyronScheduledTaskText.addTask : VyronScheduledTaskText.editTask)
                .font(VyronScheduledTaskStyle.heading).padding(VyronScheduledTaskStyle.contentPadding)
            Divider().overlay(palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: VyronScheduledTaskStyle.sectionSpacing) {
                    LabeledContent(VyronScheduledTaskText.title) {
                        TextField(VyronScheduledTaskText.title, text: $task.definition.title)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: VyronScheduledTaskStyle.compactSpacing) {
                        Text(VyronScheduledTaskText.prompt)
                        TextEditor(text: $task.definition.prompt)
                            .font(VyronScheduledTaskStyle.body).scrollContentBackground(.hidden)
                            .padding(VyronScheduledTaskStyle.compactSpacing)
                            .frame(height: VyronScheduledTaskStyle.promptHeight)
                            .background(palette.field, in: RoundedRectangle(
                                cornerRadius: VyronScheduledTaskStyle.cornerRadius
                            ))
                            .overlay(RoundedRectangle(cornerRadius: VyronScheduledTaskStyle.cornerRadius)
                                .stroke(palette.border))
                            .accessibilityLabel(VyronScheduledTaskText.prompt)
                    }
                    Picker(VyronScheduledTaskText.mode, selection: $task.definition.context.mode) {
                        ForEach(VyronScheduledTaskMode.allCases, id: \.self) { value in
                            Text(VyronScheduledTaskLabels.mode(value)).tag(value)
                        }
                    }
                    Text(VyronScheduledTaskText.editorHint)
                        .font(VyronScheduledTaskStyle.caption).foregroundStyle(palette.muted)
                    DatePicker(VyronScheduledTaskText.startsAt, selection: $task.schedule.startsAt)
                        .environment(\.timeZone, TimeZone(identifier: task.schedule.timeZoneIdentifier) ?? .current)
                    Picker(VyronScheduledTaskText.repeatSchedule, selection: $task.schedule.recurrence) {
                        ForEach(VyronTaskRecurrence.allCases, id: \.self) { value in
                            Text(VyronScheduledTaskLabels.recurrence(value)).tag(value)
                        }
                    }
                    LabeledContent(VyronScheduledTaskText.timeZone) {
                        Text(verbatim: task.schedule.timeZoneIdentifier)
                    }
                    Toggle(VyronScheduledTaskText.enabled, isOn: $task.progress.isEnabled)
                    contextSummary
                    Text(VyronScheduledTaskText.executionNote)
                        .font(VyronScheduledTaskStyle.caption).foregroundStyle(palette.muted)
                    if let error {
                        Text(verbatim: error).foregroundStyle(palette.danger).textSelection(.enabled)
                    }
                }.font(VyronScheduledTaskStyle.body).padding(VyronScheduledTaskStyle.contentPadding)
            }
            Divider().overlay(palette.border)
            HStack {
                Spacer()
                Button(VyronScheduledTaskText.cancel) { dismiss() }
                    .buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Button(VyronScheduledTaskText.save, action: saveTask)
                    .buttonStyle(AccentButtonStyle()).keyboardShortcut(.defaultAction)
            }.padding(VyronScheduledTaskStyle.cardPadding)
        }
        .frame(width: VyronScheduledTaskStyle.editorWidth, height: VyronScheduledTaskStyle.sheetHeight)
        .background(palette.canvas).foregroundStyle(palette.text).tint(palette.controlAccent)
    }

    private var contextSummary: some View {
        VStack(alignment: .leading, spacing: VyronScheduledTaskStyle.rowSpacing) {
            LabeledContent(VyronScheduledTaskText.project) {
                Text(verbatim: task.definition.context.workspacePath ?? VyronScheduledTaskText.noProject)
                    .lineLimit(2).truncationMode(.middle)
            }
            LabeledContent(VyronScheduledTaskText.model) {
                Text(verbatim: task.definition.context.model.automaticallySelect
                    ? VyronScheduledTaskText.automaticModel : task.definition.context.model.model)
            }
            LabeledContent(VyronScheduledTaskText.connection) {
                Text(task.definition.context.model.connectionID == nil
                    ? VyronScheduledTaskText.thisMac : VyronScheduledTaskText.savedConnection)
            }
            Button(VyronScheduledTaskText.useCurrentContext) {
                let mode = task.definition.context.mode
                task.definition.context = context
                task.definition.context.mode = mode
            }.buttonStyle(QuietButtonStyle())
            Text(VyronScheduledTaskText.projectHint)
                .font(VyronScheduledTaskStyle.caption).foregroundStyle(palette.muted)
        }
        .padding(VyronScheduledTaskStyle.cardPadding)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronScheduledTaskStyle.cornerRadius))
    }

    private func saveTask() {
        task.definition.title = task.definition.title.trimmingCharacters(in: .whitespacesAndNewlines)
        task.definition.prompt = task.definition.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !task.definition.title.isEmpty,
            task.definition.title.count <= VyronScheduledTaskLimits.titleCharacters
        else { error = VyronScheduledTaskText.invalidTitle; return }
        guard !task.definition.prompt.isEmpty else { error = VyronScheduledTaskText.invalidPrompt; return }
        guard task.definition.prompt.utf8.count <= VyronScheduledTaskLimits.promptBytes,
            task.definition.context.mode == .chat
                || task.definition.prompt.count <= VyronScheduledTaskLimits.agentPromptCharacters
        else {
            error = VyronScheduledTaskText.promptTooLong(
                VyronTaskPromptLimits.localizedMaximumKilobytes,
                VyronTaskPromptLimits.localizedMaximumCharacters
            )
            return
        }
        guard task.definition.context.mode == .chat || task.definition.context.workspacePath != nil else {
            error = VyronScheduledTaskText.projectRequired
            return
        }
        let now = Date()
        guard task.schedule.recurrence != .once || task.schedule.startsAt > now else {
            error = VyronScheduledTaskText.invalidDate
            return
        }
        task.progress.nextRunAt = task.schedule.nextRun(after: now)
        do {
            _ = try task.validated()
        } catch {
            self.error = VyronScheduledTaskErrorMessage.message(for: error)
            return
        }
        if save(task) {
            dismiss()
        } else {
            error = VyronScheduledTaskText.storageSaveFailed
        }
    }
}
