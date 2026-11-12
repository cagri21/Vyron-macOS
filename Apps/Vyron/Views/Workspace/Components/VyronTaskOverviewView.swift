import AppKit
import SwiftUI
import VyronCore

struct VyronTaskOverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showsAllSources = false
    @State private var selectedSourceID: UUID?

    var body: some View {
        let context = model.taskOverview
        ScrollView {
            VStack(alignment: .leading, spacing: VyronTaskOverviewStyle.sectionSpacing) {
                projectSection(context)
                outputsSection(context)
                subagentsSection(context)
                sourcesSection(context)
            }
            .padding(VyronTaskOverviewStyle.padding)
        }
        .frame(width: VyronTaskOverviewStyle.width)
        .frame(
            idealHeight: VyronTaskOverviewStyle.preferredHeight,
            maxHeight: VyronTaskOverviewStyle.maximumHeight
        )
        .font(VyronTaskOverviewStyle.body)
        .foregroundStyle(Palette.text)
        .background(Palette.surface)
        .onChange(of: context.conversationID) { _, _ in
            showsAllSources = false
            selectedSourceID = nil
        }
    }

    private func projectSection(_ context: VyronTaskOverviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: VyronTaskOverviewStyle.rowSpacing) {
            Text(verbatim: context.project.name ?? VyronHeaderText.overview)
                .font(VyronTaskOverviewStyle.heading).foregroundStyle(Palette.muted)
                .lineLimit(1).truncationMode(.middle)
            if context.project.path != nil {
                Button {
                    model.openOverviewInspector(.changes, context: context)
                    dismiss()
                } label: {
                    HStack(spacing: VyronTaskOverviewStyle.rowSpacing) {
                        Image(systemName: VyronSymbols.outputs).frame(width: VyronTaskOverviewStyle.iconWidth)
                        Text(VyronHeaderText.changes)
                        Spacer(minLength: 0)
                        Text(context.project.changes.count, format: .number)
                            .foregroundStyle(Palette.muted).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func outputsSection(_ context: VyronTaskOverviewSnapshot) -> some View {
        VStack(alignment: .leading, spacing: VyronTaskOverviewStyle.rowSpacing) {
            HStack {
                sectionTitle(VyronHeaderText.outputs)
                Spacer(minLength: 0)
                if context.project.path != nil {
                    Button {
                        model.openOverviewInspector(.files, context: context)
                        dismiss()
                    } label: { Image(systemName: VyronSymbols.plus).font(VyronTaskOverviewStyle.icon) }
                    .buttonStyle(.plain).help(VyronHeaderText.addOutput)
                    .accessibilityLabel(VyronHeaderText.addOutput)
                }
            }
            if context.project.outputs.isEmpty {
                Text(VyronHeaderText.noOutputs).foregroundStyle(Palette.muted)
            } else {
                ForEach(context.project.outputs, id: \.path) { output in
                    Button {
                        model.openOverviewOutput(output.path, context: context)
                        dismiss()
                    } label: {
                        Label {
                            Text(verbatim: output.path).lineLimit(1).truncationMode(.middle)
                        } icon: {
                            Image(systemName: VyronSymbols.files)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func subagentsSection(_ context: VyronTaskOverviewSnapshot) -> some View {
        let workers = context.response?.activity?.subagentActivities ?? []
        let isLive = context.conversationID.flatMap { conversationID in
            context.response.map { response in
                model.isResponseActivityLive(conversationID: conversationID, messageID: response.id)
            }
        } ?? false
        let working = isLive ? workers.filter { $0.activity.state == .working }.count : 0
        let done = workers.filter { $0.activity.state == .completed }.count
        return VStack(alignment: .leading, spacing: VyronTaskOverviewStyle.rowSpacing) {
            sectionTitle(VyronHeaderText.subagents)
            if workers.isEmpty {
                Text(VyronHeaderText.noSubagents).foregroundStyle(Palette.muted)
            } else {
                HStack {
                    Label(VyronHeaderText.workingCount(working), systemImage: VyronSymbols.subagents)
                    Spacer(minLength: 0)
                    Text(VyronHeaderText.doneCount(done)).foregroundStyle(Palette.muted)
                }
                ForEach(workers) { worker in
                    Button {
                        model.openOverviewActivity(context, subagentID: worker.id)
                        dismiss()
                    } label: {
                        HStack(spacing: VyronTaskOverviewStyle.compactSpacing) {
                            Text(verbatim: worker.identity.name).lineLimit(1)
                            Spacer(minLength: 0)
                            Text(VyronTrackingPresentation.status(
                                worker.activity.state == .working && !isLive ? .stopped : worker.activity.state
                            ))
                                .foregroundStyle(Palette.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if context.response != nil {
                Button {
                    model.openOverviewActivity(context)
                    dismiss()
                } label: { Label(VyronHeaderText.activity, systemImage: VyronSymbols.activityList) }
                .buttonStyle(.plain).font(VyronTaskOverviewStyle.action)
            }
        }
    }

    private func sourcesSection(_ context: VyronTaskOverviewSnapshot) -> some View {
        let sources = Array(context.sources.reversed())
        return VStack(alignment: .leading, spacing: VyronTaskOverviewStyle.rowSpacing) {
            HStack {
                sectionTitle(VyronHeaderText.sources)
                Spacer(minLength: 0)
                Button {
                    model.openScreenshotPicker()
                    dismiss()
                } label: { Image(systemName: VyronSymbols.plus).font(VyronTaskOverviewStyle.icon) }
                .buttonStyle(.plain).disabled(!model.canAttachScreenshots)
                .help(VyronHeaderText.addSource).accessibilityLabel(VyronHeaderText.addSource)
            }
            if context.sources.isEmpty {
                Text(VyronHeaderText.noSources).foregroundStyle(Palette.muted)
            } else {
                ForEach(showsAllSources ? sources : Array(sources.prefix(
                    VyronTaskOverviewStyle.visibleSourceCount
                ))) { source in
                    sourceRow(source)
                }
                if !showsAllSources, context.sources.count > VyronTaskOverviewStyle.visibleSourceCount {
                    Button(VyronHeaderText.viewAll) { showsAllSources = true }
                        .buttonStyle(.plain).font(VyronTaskOverviewStyle.action)
                }
            }
        }
    }

    private func sourceRow(_ source: VyronImageAttachment) -> some View {
        VStack(alignment: .leading, spacing: VyronTaskOverviewStyle.compactSpacing) {
            Button {
                selectedSourceID = selectedSourceID == source.id ? nil : source.id
            } label: {
                HStack(spacing: VyronTaskOverviewStyle.compactSpacing) {
                    if let image = NSImage(data: source.data) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(
                                width: VyronTaskOverviewStyle.thumbnailSize,
                                height: VyronTaskOverviewStyle.thumbnailSize
                            )
                            .clipShape(RoundedRectangle(cornerRadius: VyronTaskOverviewStyle.cornerRadius))
                    } else {
                        Image(systemName: VyronSymbols.screenshot)
                            .frame(width: VyronTaskOverviewStyle.thumbnailSize)
                    }
                    Text(verbatim: source.name).lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).help(source.name)
            .accessibilityAddTraits(selectedSourceID == source.id ? .isSelected : [])
            if selectedSourceID == source.id, let image = NSImage(data: source.data) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxHeight: VyronTaskOverviewStyle.imageHeight)
                    .accessibilityLabel(source.name)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(verbatim: title).font(VyronTaskOverviewStyle.heading).foregroundStyle(Palette.muted)
    }
}
