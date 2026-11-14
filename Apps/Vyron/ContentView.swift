import AppKit
import Combine
import SwiftUI
import VyronCore

struct ContentView: View {
    @Environment(\.locale) private var localizationLocale
    @EnvironmentObject private var model: AppModel
    @State private var sidebar = VyronWorkspaceSidebarPresentation()
    @StateObject private var plugins = VyronPluginsPresentation()
    @StateObject private var skills = VyronSkillsPresentation()
    @StateObject private var workspaceTabs = VyronWorkspaceTabsPresentation()

    var body: some View {
        let _ = localizationLocale
        GeometryReader { geometry in
            mainLayout(windowWidth: geometry.size.width)
        }
        .frame(minWidth: minimumWidth)
        .background(Palette.canvas).foregroundStyle(Palette.text).tint(Palette.controlAccent)
        .toolbarBackground(VyronSidebarStyle.railBackground, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .sheet(isPresented: Binding(
            get: { model.appNavigation.showSetup }, set: { model.appNavigation.showSetup = $0 }
        )) {
            SetupView(downloads: model.modelDownloads, selection: model.modelSelection)
                .frame(width: 660, height: 690)
        }
        .sheet(isPresented: Binding(
            get: { model.appNavigation.showAutomation }, set: { model.appNavigation.showAutomation = $0 }
        )) {
            AutomationCenter().disabled(model.isRunningScheduledTask)
        }
        .sheet(isPresented: Binding(
            get: { model.appNavigation.showScheduledTasks }, set: { model.appNavigation.showScheduledTasks = $0 }
        )) {
            VyronScheduledTasksView(
                model: model.scheduledTasks,
                context: model.scheduledTaskContext(),
                openResult: model.openScheduledTaskResult
            )
        }
        .sheet(item: Binding(
            get: { model.handoff.chatHandoffPresentation }, set: { model.handoff.chatHandoffPresentation = $0 }
        )) { presentation in
            VyronChatHandoffSheet(presentation: presentation)
        }
        .modifier(VyronMCPReviewPresenter(
            connections: model.mcpConnections, canPresent: { model.canPresentMCPReview }
        ))
        .alert(
            VyronProjectApprovalPresentation.reviewTitle(model.selectedCommandApproval?.action ?? .command),
            isPresented: Binding(
                get: { model.selectedCommandApproval != nil },
                // Approve and Cancel resolve the pending request by ID.
                set: { _ in }
            ),
            presenting: model.selectedCommandApproval
        ) { approval in
            Button(
                VyronProjectApprovalPresentation.confirmationTitle(approval.action),
                role: approval.action == .trashProjectItem ? .destructive : nil
            ) {
                model.respondToCommandApproval(true, approvalID: approval.id)
            }
            Button(VyronScheduledTaskText.cancel, role: .cancel) {
                model.respondToCommandApproval(false, approvalID: approval.id)
            }
        } message: { approval in
            Text(VyronProjectApprovalPresentation.reviewDetails(
                approval,
                workspacePath: model.selectedCommandApprovalWorkspacePath ?? VyronGeneralText.noProject,
                conversationTitle: model.selectedCommandApprovalConversationTitle
            ))
        }
        .onAppear { [model, workspaceTabs] in
            model.readRenderedWebPage = { [weak model, weak workspaceTabs] url, response, scope in
                guard let model, let workspaceTabs, model.foregroundRun.owns(response) else {
                    throw CancellationError()
                }
                if let scope {
                    return try await VyronWorkspaceBrowserReader(websiteScope: scope).read(url: url)
                }
                return try await workspaceTabs.readWebsite(
                    url,
                    selectTab: model.foregroundRun.activeResponse == response
                        && model.appNavigation.destination == .workspace
                )
            }
        }
        .onDisappear {
            model.readRenderedWebPage = nil
            model.stopGeneration()
        }
        .onChange(of: model.inspector.selectedProjectFilePath) { _, path in
            guard let path, let workspace = model.workspaceState.workspaceURL else { return }
            let url = workspace.appendingPathComponent(path).standardizedFileURL
            let root = workspace.standardizedFileURL.path + "/"
            if url.path.hasPrefix(root) { workspaceTabs.library.recordFile(url) }
        }
        .onChange(of: model.selectedConversationID) { _, _ in
            sidebar.dismissOverlay()
            workspaceTabs.selectConversation()
        }
        .onReceive(model.appNavigation.$destination.dropFirst()) { destination in
            sidebar.dismissOverlay()
            if destination == .workspace { workspaceTabs.selectConversation() }
        }
        .onChange(of: model.selectedConversation?.title) { _, title in
            workspaceTabs.tabs.updateConversationTitle(title ?? VyronBrowserText.conversation)
        }
    }

    private func mainLayout(windowWidth: CGFloat) -> some View {
        let sidebarConfiguration = VyronWorkspaceSplitConfiguration.sidebar(minimumContentWidth: minimumWorkspaceWidth)
        let isCompact = !sidebarConfiguration.canDockPanel(available: windowWidth - VyronSidebarStyle.railWidth)
        let presentation = sidebar.panelPresentation(isCompact: isCompact)

        return HStack(spacing: 0) {
            VyronNavigationRail(
                showsNewTask: model.appNavigation.destination == .workspace && presentation != .docked
            )
            if model.appNavigation.destination == .settings {
                VyronSettingsView()
            } else {
                destinationContent(
                    sidebarPresentation: Binding(
                        get: { sidebar.panelPresentation(isCompact: isCompact) },
                        set: { if $0 == .hidden { sidebar.dismissOverlay() } }
                    ),
                    sidebarConfiguration: sidebarConfiguration
                )
            }
        }
        .toolbar {
            VyronWorkspaceToolbar(
                isSidebarPresented: presentation != .hidden,
                toggleSidebar: { sidebar.toggle(isCompact: isCompact) },
                showConversation: workspaceTabs.selectConversation
            )
            ToolbarItem(placement: .primaryAction) {
                if model.appNavigation.destination == .workspace {
                    VyronWorkspaceToolsButton()
                        .environmentObject(workspaceTabs.library)
                        .environmentObject(workspaceTabs)
                }
            }
            .vyronPlainStyle()
        }
        .onChange(of: isCompact) { _, _ in sidebar.dismissOverlay() }
        .onExitCommand(perform: presentation == .overlay ? { sidebar.dismissOverlay() } : nil)
    }

    private func destinationContent(
        sidebarPresentation: Binding<VyronWorkspacePanelPresentation>,
        sidebarConfiguration: VyronWorkspaceSplitConfiguration
    ) -> some View {
        Group {
            if model.appNavigation.destination == .plugins {
                VyronCustomizeSidebar(connections: model.mcpConnections, presentation: plugins)
                    .frame(width: VyronPluginsStyle.sidebarWidth)
                Rectangle().fill(Palette.border).frame(width: VyronWorkspaceStyle.dividerWidth)
            }
            if model.appNavigation.destination == .plugins {
                if plugins.section == .skills {
                    VyronSkillsView(presentation: skills, projectDirectory: model.workspaceState.workspaceURL)
                } else {
                    VyronPluginsView(connections: model.mcpConnections, presentation: plugins)
                }
            } else {
                VyronWorkspaceSplitView(
                    presentation: sidebarPresentation,
                    configuration: sidebarConfiguration
                ) {
                    ProjectSidebar(presentation: sidebarPresentation.wrappedValue)
                } content: {
                    workspace
                }
            }
        }
    }

    private var minimumWidth: CGFloat {
        if model.appNavigation.destination == .settings {
            return VyronSidebarStyle.railWidth + VyronSettingsStyle.minimumWidth
        }
        if model.appNavigation.destination == .plugins {
            return VyronSidebarStyle.railWidth + VyronPluginsStyle.sidebarWidth + VyronPluginsStyle.minimumPageWidth
        }
        return max(VyronWorkspaceStyle.minimumWindowWidth, minimumWorkspaceWidth + VyronSidebarStyle.railWidth)
    }

    private var minimumWorkspaceWidth: CGFloat {
        VyronWorkspaceStyle.minimumConversationWidth
            + (showsInspector && workspaceTabs.tabs.selectedTab.kind == .conversation
                ? VyronWorkspaceStyle.minimumInspectorWidth + VyronWorkspaceStyle.dividerWidth : 0)
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            if workspaceTabs.tabs.selectedTab.kind != .conversation {
                VyronWorkspaceTabBar()
                VyronWorkspaceBrowserChrome()
            }
            VyronWorkspaceTabContent { conversationWorkspace }
        }
        .environmentObject(workspaceTabs)
        .environmentObject(workspaceTabs.library)
        .focusedSceneObject(workspaceTabs)
        .onAppear {
            workspaceTabs.tabs.updateConversationTitle(model.selectedConversation?.title ?? VyronBrowserText.conversation)
        }
    }

    private var conversationWorkspace: some View {
        VStack(spacing: 0) {
            if !model.isConversationModeLocked {
                VyronWorkspaceHeader()
            }
            VyronWorkspaceTerminalSplitView(isPresented: !model.isChatWorkspace && model.inspector.showTerminal) {
                DevelopmentTerminal()
            } content: {
                VyronWorkspaceSplitView(
                    presentation: .constant(showsInspector ? .docked : .hidden),
                    configuration: .inspector
                ) {
                    if model.appNavigation.trackingSelection != nil {
                        VyronActivityPanel()
                    } else {
                        ProjectInspector()
                    }
                } content: {
                    workspaceContent
                        .modifier(VyronComposerDropTarget())
                }
            }
        }
    }

    private var showsInspector: Bool {
        model.isWorkspaceInspectorVisible
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if model.messages.isEmpty {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: VyronWorkspaceStyle.welcomeSpacing) {
                        Text(
                            model.composer.mode == .chat
                                ? VyronWorkspaceText.welcomeChat : VyronWorkspaceText.welcomeWork
                        )
                        .font(VyronWorkspaceStyle.heading)
                        .multilineTextAlignment(.center)
                        VyronComposer()
                    }
                    .frame(maxWidth: VyronWorkspaceStyle.contentWidth)
                    .padding(VyronWorkspaceStyle.outerPadding)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }
        } else {
            VStack(spacing: 0) {
                ConversationView()
                VyronComposer()
                    .frame(maxWidth: VyronWorkspaceStyle.contentWidth)
                    .padding(VyronWorkspaceStyle.outerPadding)
                    .frame(maxWidth: .infinity)
            }
        }
    }

}
