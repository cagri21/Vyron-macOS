extension AppModel {
    func openSettings(_ section: VyronSettingsSection = .general) {
        voice.end()
        appNavigation.settingsSection = section
        appNavigation.destination = .settings
    }

    func openPlugins() {
        voice.end()
        appNavigation.destination = .plugins
    }

    func returnToWorkspace() {
        appNavigation.destination = .workspace
    }
}
