import Foundation
import VyronDevelopment

extension AppModel {
    /// Called only after the user adds a project, never by restoration or read-only tools.
    func loadAddedWorkspace(_ url: URL, expectedSelectionID: UUID) async {
        guard composerAttachments.generation == expectedSelectionID else { return }
        let failure = await Task.detached(priority: .userInitiated) {
            Self.createMissingProjectSetup(in: url)
        }.value
        guard composerAttachments.generation == expectedSelectionID else { return }
        reportProjectSetupFailures(failure.map { [$0] } ?? [])
        await loadWorkspace(url, expectedSelectionID: expectedSelectionID)
    }

    func initializeAddedProjectFolders(_ folders: [URL]) {
        guard !folders.isEmpty else { return }
        reportProjectSetupFailures(folders.compactMap(Self.createMissingProjectSetup))
    }

    private nonisolated static func createMissingProjectSetup(in folder: URL) -> String? {
        do {
            _ = try VyronProjectSetup.prepare(at: folder)
            return nil
        } catch {
            return "\(folder.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func reportProjectSetupFailures(_ failures: [String]) {
        if let projectSetupError = workspaceState.projectSetupError, errorMessage == projectSetupError {
            errorMessage = nil
        }
        workspaceState.projectSetupError = failures.isEmpty
            ? nil : VyronWorkspaceText.projectSetupFailure(failures.joined(separator: "\n"))
        if let projectSetupError = workspaceState.projectSetupError { errorMessage = projectSetupError }
    }
}
