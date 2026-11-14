import SwiftUI
import VyronCore

struct ProjectSidebar: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject var model: AppModel
    @State var nameRequest: VyronSidebarNameRequest?
    @State var editingProject: VyronSidebarProjectSelection?
    @State var chatSchedulingTemplate: VyronChatSchedulingTemplate?
    @State private var showsArchivedChats = false
    @State var expandedChatProjects: Set<String> = []
    @State private var showsSearch = false
    @State private var showsNotifications = false
    @FocusState private var newTaskFocused: Bool
    @FocusState private var searchFocused: Bool
    let presentation: VyronWorkspacePanelPresentation

    init(presentation: VyronWorkspacePanelPresentation) {
        self.presentation = presentation
    }

    var query: String { model.sidebarState.sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isSearching: Bool { !query.isEmpty }

    var body: some View {
        let _ = localizationLocale
        VStack(alignment: .leading, spacing: 0) {
            header
            newTask
            ZStack {
                VStack(spacing: 0) {
                    if showsSearch || isSearching { searchField }
                    projectList
                }
                .opacity(showsNotifications ? 0 : 1)
                .disabled(showsNotifications)
                .allowsHitTesting(!showsNotifications)
                .accessibilityHidden(showsNotifications)
                if showsNotifications {
                    VyronNotificationsView()
                }
            }
            scheduledTasks
            engineStatus
        }
        .background(VyronSidebarStyle.background)
        .onChange(of: showsNotifications) { _, isPresented in
            if isPresented { searchFocused = false }
        }
        .onChange(of: presentation) { _, presentation in
            newTaskFocused = presentation == .overlay
            if presentation == .hidden { searchFocused = false }
        }
        .sheet(item: $nameRequest) { request in
            VyronSidebarNameEditor(title: request.title, initialValue: request.initialValue) { name in
                saveName(name, request: request)
            }
        }
        .sheet(item: $editingProject) { project in
            VyronSidebarProjectEditor(projectPath: project.path).environmentObject(model)
        }
        .sheet(item: $chatSchedulingTemplate) { template in
            VyronScheduledTaskEditor(
                initial: nil,
                context: template.definition.context,
                save: model.scheduledTasks.save,
                template: template.definition
            )
        }
        .sheet(isPresented: $showsArchivedChats) {
            VyronSidebarArchivedChatsView().environmentObject(model)
        }
    }

    private var header: some View {
        HStack(spacing: VyronSidebarStyle.controlSpacing) {
            Menu {
                Button(VyronSidebarText.newTask) { model.requestNewTask() }
                Button(VyronSidebarText.openProject) { model.chooseWorkspace() }
                Button(VyronSidebarText.newFolder) { requestNewFolder(parentID: nil) }
                Divider()
                Button(VyronSidebarText.archivedChats) { showsArchivedChats = true }
            } label: {
                HStack(spacing: VyronSidebarStyle.controlSpacing) {
                    Text(VyronSidebarText.brand).font(VyronSidebarStyle.brandFont)
                    Image(systemName: VyronSymbols.chevronDown)
                        .font(VyronSidebarStyle.headerDisclosureFont)
                }
                .foregroundStyle(Palette.text)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Palette.text)
            .font(VyronSidebarStyle.brandFont)
            .fixedSize()

            Spacer(minLength: 0)
            Menu {
                Button(VyronSidebarText.openProject) { model.chooseWorkspace() }
                Button(VyronSidebarText.newFolder) { requestNewFolder(parentID: nil) }
            } label: {
                Image(systemName: VyronSymbols.plus)
                    .font(VyronSidebarStyle.headerActionFont)
                    .foregroundStyle(Palette.text)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Palette.text)
            .font(VyronSidebarStyle.headerActionFont)
            .fixedSize()
            .help(VyronSidebarText.addToSidebar)
            .accessibilityLabel(VyronSidebarText.addToSidebar)

            VyronNotificationBell(isPresented: $showsNotifications)

            Button {
                showsNotifications = false
                showsSearch = true
                searchFocused = true
            } label: {
                Image(systemName: VyronSymbols.search)
            }
            .buttonStyle(.plain)
            .help(VyronSidebarText.search)
            .accessibilityLabel(VyronSidebarText.search)
        }
        .font(VyronSidebarStyle.iconFont)
        .padding(.horizontal, VyronSidebarStyle.headerInset)
        .frame(height: VyronSidebarStyle.headerHeight)
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VyronSidebarStyle.rowSpacing) {
                ForEach(entries) { entry in
                    entryView(entry)
                        .padding(
                            .leading,
                            min(
                                CGFloat(entry.depth) * VyronSidebarStyle.indentation,
                                VyronSidebarStyle.maximumIndent
                            )
                        )
                }
            }
            .padding(.horizontal, VyronSidebarStyle.listInset)
            .padding(.bottom, VyronSidebarStyle.sectionSpacing)
        }
        .scrollIndicators(.hidden)
    }

    private var newTask: some View {
        Button {
            model.requestNewTask()
        } label: {
            HStack(spacing: VyronSidebarStyle.rowContentSpacing) {
                Image(systemName: VyronSymbols.newTask)
                    .frame(width: VyronSidebarStyle.rowIconWidth)
                Text(VyronSidebarText.newTask)
                Spacer(minLength: 0)
            }
            .font(VyronSidebarStyle.rowFont)
            .padding(.horizontal, VyronSidebarStyle.rowInset)
            .frame(height: VyronSidebarStyle.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($newTaskFocused)
        .modifier(VyronSidebarRowBackground())
        .padding(.horizontal, VyronSidebarStyle.listInset)
        .padding(.bottom, VyronSidebarStyle.controlSpacing)
        .help(VyronSidebarText.newTask + " (⌘N)")
    }

    private var searchField: some View {
        HStack(spacing: VyronSidebarStyle.controlSpacing) {
            Image(systemName: VyronSymbols.search).foregroundStyle(Palette.muted)
            TextField(
                VyronSidebarText.searchPlaceholder,
                text: Binding(
                    get: { model.sidebarState.sidebarSearchText },
                    set: { model.sidebarState.sidebarSearchText = $0 }
                )
            )
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel(VyronSidebarText.searchAccessibility)
                .onExitCommand {
                    model.sidebarState.sidebarSearchText = ""
                    showsSearch = false
                }
            Button {
                model.sidebarState.sidebarSearchText = ""
                showsSearch = false
            } label: {
                Image(systemName: VyronSymbols.searchClear).foregroundStyle(Palette.muted)
            }
            .buttonStyle(.plain)
            .help(VyronSidebarText.clearSearch)
            .accessibilityLabel(VyronSidebarText.clearSearch)
        }
        .font(VyronSidebarStyle.detailFont)
        .padding(VyronSidebarStyle.rowInset)
        .background(Palette.field, in: RoundedRectangle(cornerRadius: VyronSidebarStyle.rowRadius))
        .padding(.horizontal, VyronSidebarStyle.listInset)
        .padding(.bottom, VyronSidebarStyle.controlSpacing)
    }

    private var scheduledTasks: some View {
        Button {
            model.appNavigation.showScheduledTasks = true
        } label: {
            HStack(spacing: VyronSidebarStyle.rowContentSpacing) {
                Image(systemName: VyronSymbols.clock)
                    .frame(width: VyronSidebarStyle.rowIconWidth)
                Text(VyronScheduledTaskText.scheduledTasks)
                Spacer(minLength: 0)
            }
            .font(VyronSidebarStyle.rowFont)
            .padding(.horizontal, VyronSidebarStyle.rowInset)
            .frame(height: VyronSidebarStyle.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(VyronSidebarRowBackground(isSelected: model.appNavigation.showScheduledTasks))
        .padding(.horizontal, VyronSidebarStyle.listInset)
        .padding(.bottom, VyronSidebarStyle.controlSpacing)
        .help(VyronScheduledTaskText.scheduledTasks)
        .accessibilityLabel(VyronScheduledTaskText.scheduledTasks)
    }

    private var engineStatus: some View {
        Button {
            model.appNavigation.showSetup = true
        } label: {
            HStack(spacing: VyronSidebarStyle.rowContentSpacing) {
                Circle().fill(model.modelSelection.isConnected ? Palette.success : Palette.warning)
                    .frame(width: VyronSidebarStyle.statusSize, height: VyronSidebarStyle.statusSize)
                VStack(alignment: .leading, spacing: VyronSidebarStyle.rowSpacing) {
                    Text(model.modelSelection.connectionLabel).font(VyronSidebarStyle.detailFont)
                    Text(
                        model.modelSelection.isBuiltinConnection
                            ? VyronSidebarText.localConnection
                            : "\(model.modelSelection.activeConnectionName) · \(model.modelSelection.inferenceLocationLabel)"
                    )
                    .font(VyronSidebarStyle.captionFont)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(VyronSidebarStyle.footerInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(VyronSidebarText.manageModels)
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.border).frame(height: VyronWorkspaceStyle.dividerWidth)
        }
    }
}
