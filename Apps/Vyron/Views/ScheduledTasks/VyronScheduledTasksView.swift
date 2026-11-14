import SwiftUI
import VyronCore

struct VyronScheduledTasksView: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var model: VyronScheduledTasksModel
    let context: VyronScheduledTaskContext
    let openResult: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing: VyronScheduledTask?
    @State private var creating = false
    @State private var removing: VyronScheduledTask?

    init(
        model: VyronScheduledTasksModel,
        context: VyronScheduledTaskContext,
        openResult: @escaping (UUID) -> Void
    ) {
        self.model = model
        self.context = context
        self.openResult = openResult
    }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(VyronScheduledTaskText.scheduledTasks).font(VyronScheduledTaskStyle.heading)
                Spacer()
                Button { dismiss() } label: { Image(systemName: VyronSymbols.close) }
                    .buttonStyle(QuietButtonStyle()).help(VyronScheduledTaskText.close)
            }.padding(VyronScheduledTaskStyle.contentPadding)
            Divider().overlay(palette.border)
            ScrollView {
                VStack(alignment: .leading, spacing: VyronScheduledTaskStyle.sectionSpacing) {
                    Button { creating = true } label: {
                        Label(VyronScheduledTaskText.addTask, systemImage: VyronSymbols.plus)
                    }.buttonStyle(AccentButtonStyle())
                    Text(VyronScheduledTaskText.executionNote)
                        .font(VyronScheduledTaskStyle.body).foregroundStyle(palette.muted)
                    Text(VyronScheduledTaskText.reviewNote)
                        .font(VyronScheduledTaskStyle.caption).foregroundStyle(palette.muted)
                    if let error = model.errorMessage {
                        Label(error, systemImage: VyronSymbols.warning)
                            .font(VyronScheduledTaskStyle.body).foregroundStyle(palette.warning)
                            .textSelection(.enabled)
                    }
                    if model.tasks.isEmpty { emptyState }
                    ForEach(model.tasks) { task in
                        VyronScheduledTaskCard(
                            task: task,
                            model: model,
                            actions: VyronScheduledTaskCardActions(
                                edit: { editing = task },
                                remove: { removing = task },
                                openResult: { id in dismiss(); openResult(id) }
                            )
                        )
                    }
                }.padding(VyronScheduledTaskStyle.contentPadding)
            }
        }
        .frame(width: VyronScheduledTaskStyle.sheetWidth, height: VyronScheduledTaskStyle.sheetHeight)
        .background(palette.canvas).foregroundStyle(palette.text).tint(palette.controlAccent)
        .sheet(isPresented: $creating) {
            VyronScheduledTaskEditor(initial: nil, context: context, save: model.save)
        }
        .sheet(item: $editing) { task in
            VyronScheduledTaskEditor(initial: task, context: context, save: model.save)
        }
        .alert(VyronScheduledTaskText.removeTitle, isPresented: removingBinding, presenting: removing) { task in
            Button(VyronScheduledTaskText.remove, role: .destructive) {
                model.remove(task.id)
                removing = nil
            }
            Button(VyronScheduledTaskText.cancel, role: .cancel) { removing = nil }
        } message: { _ in
            Text(VyronScheduledTaskText.removeMessage)
        }
    }

    private var removingBinding: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: VyronScheduledTaskStyle.rowSpacing) {
            Image(systemName: VyronSymbols.clock).font(VyronScheduledTaskStyle.heading)
            Text(VyronScheduledTaskText.noTasksTitle).font(VyronScheduledTaskStyle.title)
            Text(VyronScheduledTaskText.noTasksBody)
                .font(VyronScheduledTaskStyle.body).foregroundStyle(palette.muted)
        }
        .padding(VyronScheduledTaskStyle.contentPadding).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronScheduledTaskStyle.cornerRadius))
    }
}
