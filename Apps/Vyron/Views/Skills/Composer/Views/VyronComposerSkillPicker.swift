import SwiftUI
import VyronCore

struct VyronComposerSkillPicker: View {
    @Environment(\.vyronPalette) private var palette
    @Environment(\.locale) private var localizationLocale
    @ObservedObject var skills: VyronComposerSkillsModel
    @Binding var draft: String
    let projectDirectory: URL?
    let submit: () -> Void

    var body: some View {
        let _ = localizationLocale
        Group {
            if skills.isPresented {
                VStack(alignment: .leading, spacing: VyronComposerSkillStyle.sectionSpacing) {
                    header
                    content
                    Text(VyronSkillText.pickerKeyboardHint)
                        .font(VyronComposerSkillStyle.caption)
                        .foregroundStyle(palette.muted)
                }
                .padding(VyronComposerSkillStyle.padding)
                .background(palette.surface, in: RoundedRectangle(cornerRadius: VyronComposerSkillStyle.radius))
                .overlay(RoundedRectangle(cornerRadius: VyronComposerSkillStyle.radius).stroke(palette.border))
                .accessibilityElement(children: .contain)
                .accessibilityLabel(VyronSkillText.title)
            }
        }
        .onChange(of: draft, initial: true) { _, value in skills.updateDraft(value) }
        .task(id: VyronSkillLoadRequest(projectDirectory: projectDirectory, refreshID: skills.refreshID)) {
            await skills.load(projectDirectory: projectDirectory)
        }
    }

    private var header: some View {
        HStack(spacing: VyronComposerSkillStyle.sectionSpacing) {
            Label(VyronSkillText.title, systemImage: VyronSymbols.skills)
            Spacer(minLength: 0)
            if skills.isLoading {
                ProgressView().controlSize(.small).help(VyronSkillText.loading)
            }
            Button { skills.refresh() } label: {
                Image(systemName: VyronSymbols.refresh)
            }
            .disabled(skills.isLoading)
            .help(VyronSkillText.refresh)
            .accessibilityLabel(VyronSkillText.refresh)
            Button { skills.dismiss() } label: {
                Image(systemName: VyronSymbols.close)
            }
            .help(VyronWorkspaceText.dismissError)
            .accessibilityLabel(VyronWorkspaceText.dismissError)
        }
        .font(VyronComposerSkillStyle.caption)
        .foregroundStyle(palette.muted)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if skills.hasLoadError {
            HStack(spacing: VyronComposerSkillStyle.sectionSpacing) {
                Text(VyronSkillText.loadFailed)
                Spacer(minLength: 0)
                Button(VyronSkillText.retry) { skills.refresh() }
                    .buttonStyle(.plain)
            }
            .font(VyronComposerSkillStyle.caption)
            .foregroundStyle(palette.warning)
        }
        if skills.visibleCommands.isEmpty {
            if skills.isLoading {
                ProgressView(VyronSkillText.loading).controlSize(.small)
            } else if !skills.hasLoadError {
                Text(skills.inventory?.skills.isEmpty != false
                    ? VyronSkillText.emptyTitle : VyronSkillText.noResults)
                    .font(VyronComposerSkillStyle.body)
                    .foregroundStyle(palette.muted)
            }
        } else {
            commandList
        }
        if skills.inventory?.didReachLimit == true {
            Text(VyronSkillText.scanLimit)
                .font(VyronComposerSkillStyle.caption)
                .foregroundStyle(palette.warning)
        } else if skills.inventory?.issues.isEmpty == false {
            Text(VyronSkillText.scanWarning)
                .font(VyronComposerSkillStyle.caption)
                .foregroundStyle(palette.warning)
        }
    }

    private var commandList: some View {
        let commands = skills.visibleCommands
        let selectedID = skills.selectedCommand?.id
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: VyronComposerSkillStyle.rowSpacing) {
                    ForEach(commands) { command in
                        VyronComposerSkillRow(
                            command: command,
                            isSelected: command.id == selectedID
                        ) {
                            if let replacement = skills.replacement(for: command, in: draft) {
                                draft = replacement
                                if case .side = command { submit() }
                            }
                        }
                        .id(command.id)
                    }
                }
            }
            .frame(height: min(
                CGFloat(commands.count) * VyronComposerSkillStyle.rowHeight,
                VyronComposerSkillStyle.maximumListHeight
            ))
            .onChange(of: skills.selectedCommand?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}
