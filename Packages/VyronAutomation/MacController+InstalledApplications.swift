import AppKit
import Foundation

extension MacController {
    /// Lists running apps and app bundles in the standard application directories.
    public func availableApplications() -> [DesktopApplication] {
        var byID = Dictionary(applications().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for identifier in AutomationPolicy.automaticLaunchApplicationIDs where byID[identifier] == nil {
            byID[identifier] = registeredCatalogApplication(for: identifier)?.application
        }
        for installed in discoveredApplications() where byID[installed.id] == nil {
            byID[installed.id] = installed.application
        }
        return byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func launch(applicationID: String) async throws -> DesktopApplication {
        try Task.checkCancellation()
        if let running = applications().first(where: { $0.id == applicationID }) {
            try activate(application: running)
            return running
        }
        guard let installed = installedCatalogApplication(for: applicationID) else {
            throw MacControlError.applicationUnavailable
        }
        return try await launchApplication(at: installed.url, expectedApplicationID: applicationID)
    }

    public func launch(application: DesktopApplication) async throws -> DesktopApplication {
        try Task.checkCancellation()
        guard let url = validatedInstallationURL(for: application) else {
            throw MacControlError.applicationUnavailable
        }
        return try await launchApplication(at: url, expectedApplicationID: application.id)
    }

    func validatedInstallationURL(for application: DesktopApplication) -> URL? {
        guard let installed = installedCatalogApplication(for: application.id),
            installed.application == application
        else { return nil }
        return installed.url
    }

    func installedCatalogApplication(for applicationID: String) -> VyronInstalledApplication? {
        if AutomationPolicy.automaticLaunchApplicationIDs.contains(applicationID) {
            return registeredCatalogApplication(for: applicationID)
        }
        return discoveredApplications().first { $0.id == applicationID }
    }

    private func discoveredApplications() -> [VyronInstalledApplication] {
        VyronInstalledApplicationCatalog.applications(in: applicationDirectories).filter {
            !AutomationPolicy.automaticLaunchApplicationIDs.contains($0.id)
        }
    }

    private func registeredCatalogApplication(for applicationID: String) -> VyronInstalledApplication? {
        guard let url = registeredApplicationURL(for: applicationID),
            let installed = VyronInstalledApplicationCatalog.application(at: url),
            installed.id == applicationID
        else { return nil }
        return installed
    }

    private func registeredApplicationURL(for applicationID: String) -> URL? {
        let registeredURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: applicationID)
        guard VyronXcodeApplicationCatalog.applicationIDs.contains(applicationID) else { return registeredURL }
        let xcodeURL = registeredURL == nil
            ? NSWorkspace.shared.urlForApplication(withBundleIdentifier: VyronXcodeApplicationCatalog.xcodeID)
            : nil
        return VyronXcodeApplicationCatalog.applicationURL(
            for: applicationID,
            registeredURL: registeredURL,
            xcodeURL: xcodeURL
        )
    }
}
