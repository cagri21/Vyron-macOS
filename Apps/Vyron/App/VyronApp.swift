import SwiftUI

@main
struct VyronApp: App {
    @NSApplicationDelegateAdaptor(VyronAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel(storagePaths: .applicationSupport, preferences: .standard)
    @StateObject private var localization = VyronLocalization()

    var body: some Scene {
        Window("Vyron", id: VyronAppWindow.main) {
            ContentView()
                .environmentObject(model)
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
                .preferredColorScheme(.dark)
                .frame(
                    minWidth: VyronWorkspaceStyle.minimumWindowWidth,
                    minHeight: VyronWorkspaceStyle.minimumWindowHeight
                )
                .task {
                    appDelegate.model = model
                    await model.start()
                }
                .onOpenURL { url in model.openChatDeepLink(url) }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(
            width: VyronWorkspaceStyle.defaultWindowWidth,
            height: VyronWorkspaceStyle.defaultWindowHeight
        )
        .defaultPosition(.center)
        .commands {
            VyronWorkspaceTabCommands()
            CommandGroup(replacing: .newItem) {
                Button(VyronGeneralText.newTask) { model.requestNewTask() }
                    .keyboardShortcut("n", modifiers: .command)
                Button(VyronGeneralText.chooseWorkspace) { model.chooseWorkspace() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandGroup(after: .appSettings) {
                Button(VyronWorkspaceText.manageModels) { model.appNavigation.showSetup = true }
                Button(VyronPluginText.title) { model.openPlugins() }
                Button(VyronScheduledTaskText.scheduledTasks) { model.appNavigation.showScheduledTasks = true }
            }
        }

        WindowGroup("Vyron", id: VyronAppWindow.conversation, for: UUID.self) { value in
            if let conversationID = value.wrappedValue {
                VyronConversationWindowView(conversationID: conversationID)
                    .environmentObject(model)
                    .environmentObject(localization)
                    .environment(\.locale, localization.locale)
                    .preferredColorScheme(.dark)
                    .frame(
                        minWidth: VyronConversationWindowStyle.minimumWidth,
                        minHeight: VyronConversationWindowStyle.minimumHeight
                    )
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(
            width: VyronConversationWindowStyle.defaultWidth,
            height: VyronConversationWindowStyle.defaultHeight
        )

        Settings {
            VyronSettingsView()
                .environmentObject(model)
                .environmentObject(localization)
                .environment(\.locale, localization.locale)
                .preferredColorScheme(.dark)
                .frame(minWidth: VyronSettingsStyle.minimumWidth, minHeight: VyronSettingsStyle.minimumHeight)
        }
        .defaultSize(width: VyronSettingsStyle.preferredWidth, height: VyronSettingsStyle.preferredHeight)
    }
}
