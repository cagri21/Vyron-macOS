import Foundation
import VyronCore
import VyronModelData

extension AppModel {
    convenience init(
        storagePaths: VyronAppStoragePaths,
        preferences: UserDefaults,
        modelOverrides: VyronAppModelOverrides = VyronAppModelOverrides(),
        voice: VyronVoiceModel? = nil
    ) {
        let credentialStore = ModelCredentialStore()
        let credentials = VyronAppModelCredentialServices(
            store: credentialStore,
            reader: VyronModelCredentialReader(store: credentialStore),
            localAuthentication: VyronLocalAuthenticationModel(
                backup: VyronLocalCredentialBackup(baseDirectory: storagePaths.url(for: .localAuthentication))
            )
        )
        let conversation = VyronAppConversationDependencies(
            historyStore: VyronConversationHistoryStore(historyURL: storagePaths.url(for: .conversationHistory)),
            notifications: VyronNotificationsModel(
                readStore: VyronNotificationReadStore(fileURL: storagePaths.url(for: .notificationReadState))
            ),
            voice: voice ?? VyronVoiceModel(service: VyronMacSpeechService(), defaults: preferences)
        )
        let models = VyronAppModelDependencies(
            selection: VyronModelSelectionModel(
                builtinClient: modelOverrides.builtinClient,
                store: ModelConnectionStore(fileURL: storagePaths.url(for: .modelConnections)),
                preferences: VyronBuiltinModelPreferences(defaults: preferences),
                providers: VyronModelProviderBuilders(
                    builtin: { try OllamaClient(settings: $0) },
                    configured: { profile, key in try VyronModelProviderFactory.makeProvider(for: profile, apiKey: key) },
                    autoLocal: modelOverrides.autoLocal ?? VyronAutoLocalServices(makeProvider: { profile in
                        let key = try await credentials.reader.key(for: profile.id)
                        try Task.checkCancellation()
                        return try VyronModelProviderFactory.makeProvider(
                            for: profile, apiKey: key, automaticReasoning: true
                        )
                    })
                )
            ),
            downloads: VyronModelDownloads(
                pausedDownloads: VyronPausedModelDownloadsStore(defaults: preferences),
                storageDirectory: storagePaths.directory
            ),
            balances: VyronConnectionBalancesModel(
                dependencies: modelOverrides.balances ?? VyronConnectionBalanceDependencies(
                    repository: VyronConnectionBalanceClient(),
                    credential: { try credentialStore.key(for: $0) },
                    clock: .continuous
                ),
                estimateStore: VyronEstimatedBalanceStore(fileURL: storagePaths.url(for: .estimatedBalances))
            ),
            credentials: credentials
        )
        let workspace = VyronAppWorkspaceDependencies(
            sidebar: VyronSidebarState(
                store: SidebarOrganizationStore(fileURL: storagePaths.url(for: .sidebar))
            ),
            mcpConnections: MCPConnectionsModel(
                store: MCPConnectionStore(fileURL: storagePaths.url(for: .mcpConnections))
            ),
            scheduledTasks: VyronScheduledTasksModel(
                store: VyronScheduledTaskStore(fileURL: storagePaths.url(for: .scheduledTasks))
            )
        )
        self.init(preferences: preferences, conversation: conversation, workspace: workspace, models: models)
    }

    convenience init(
        historyDirectory: URL? = nil,
        client: OllamaClient = OllamaClient(),
        voice: VyronVoiceModel? = nil,
        balanceDependencies: VyronConnectionBalanceDependencies? = nil
    ) {
        self.init(
            storagePaths: historyDirectory.map { VyronAppStoragePaths(directory: $0) } ?? .applicationSupport,
            preferences: .standard,
            modelOverrides: VyronAppModelOverrides(builtinClient: client, balances: balanceDependencies),
            voice: voice
        )
    }
}
