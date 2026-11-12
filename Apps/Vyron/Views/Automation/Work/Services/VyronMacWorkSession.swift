import Foundation
import VyronAutomation
import VyronCore

/// A single Work response owns its native observations, approvals and cancellation boundary.
@MainActor
final class VyronMacWorkSession {
    let context: VyronMacWorkContext
    let dependencies: VyronMacWorkDependencies
    private(set) var currentProjectRoot: URL?
    var snapshots: [String: VyronMacWorkSnapshot] = [:]
    var declinedActions: Set<String> = []
    var didRequestAccessibility = false
    let maximumSnapshotAge: TimeInterval = 30
    let maximumSnapshots = 8

    init(context: VyronMacWorkContext, dependencies: VyronMacWorkDependencies) {
        self.context = context
        self.dependencies = dependencies
        currentProjectRoot = context.projectRoot
    }

    func updateProjectRoot(_ root: URL) throws {
        try validateCurrent()
        let canonical = root.standardizedFileURL
        guard canonical.isFileURL, canonical.resolvingSymlinksInPath() == canonical,
            try FileManager.default.attributesOfItem(
                atPath: canonical.path
            )[.type] as? FileAttributeType == .typeDirectory
        else { throw argumentError() }
        currentProjectRoot = canonical
        snapshots.removeAll()
    }

    func execute(_ call: DevelopmentToolCall) async throws -> DevelopmentExternalResult {
        try validateCurrent()
        do {
            guard let definition = VyronMacWorkTools.definitions.first(where: { $0.name == call.function.name }) else {
                throw argumentError()
            }
            guard definition.isReadOnly || context.allowsActions else {
                throw VyronMacWorkError(message: "Plan mode can inspect Mac apps but cannot open or control them.")
            }
            switch call.function.name {
            case VyronMacWorkTools.apps:
                try requireArguments(call, keys: [])
                return try applicationList()
            case VyronMacWorkTools.inspect:
                try requireArguments(call, keys: ["application_id"])
                let app = try runningApplication(id: applicationID(call))
                if !dependencies.controller.permissions.accessibilityGranted, !didRequestAccessibility {
                    didRequestAccessibility = true
                    dependencies.controller.requestAccessibility()
                    try validateCurrent()
                }
                let observation = try dependencies.controller.inspect(application: app)
                try validateCurrent()
                guard observation.applicationID == app.id else { throw argumentError() }
                snapshots[app.id] = VyronMacWorkSnapshot(application: app, observation: observation)
                if snapshots.count > maximumSnapshots,
                    let oldest = snapshots.min(by: {
                        $0.value.observation.capturedAt < $1.value.observation.capturedAt
                    }) {
                    snapshots.removeValue(forKey: oldest.key)
                }
                return try result([
                    "application_id": .string(app.id), "snapshot_id": .string(observation.id.uuidString),
                    "captured_at": .number(observation.capturedAt.timeIntervalSince1970),
                    "text": .string(observation.text)
                ])
            case VyronMacWorkTools.openApp:
                return try await openApplication(call)
            case VyronMacWorkTools.openProject:
                return try await openProject(call)
            case VyronMacWorkTools.click, VyronMacWorkTools.typeText, VyronMacWorkTools.pressKey:
                return try await controlApplication(call)
            default:
                throw argumentError()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return DevelopmentExternalResult(text: error.localizedDescription, isError: true)
        }
    }

    func runningApplication(id: String) throws -> DesktopApplication {
        try validateCurrent()
        guard let app = dependencies.controller.applications().first(where: { $0.id == id }),
            app.processIdentifier > 0 else {
            throw VyronMacWorkError(message: "Use a running application_id returned by vyron_mac_apps. "
                + "Open the app first when it is installed but not running.")
        }
        return app
    }

    func validateCurrent() throws {
        try Task.checkCancellation()
        try dependencies.validateCurrent()
    }

    func result(_ payload: [String: DevelopmentJSONValue]) throws -> DevelopmentExternalResult {
        let data = try JSONEncoder().encode(payload)
        return DevelopmentExternalResult(text: String(decoding: data, as: UTF8.self))
    }

    private func applicationList() throws -> DevelopmentExternalResult {
        let permissions = dependencies.controller.permissions
        let apps = dependencies.controller.availableApplications().prefix(128).map { app in
            DevelopmentJSONValue.object([
                "application_id": .string(app.id), "name": .string(app.name),
                "is_running": .bool(app.processIdentifier > 0)
            ])
        }
        return try result([
            "applications": .array(apps), "accessibility_granted": .bool(permissions.accessibilityGranted),
            "screen_capture_granted": .bool(permissions.screenCaptureGranted)
        ])
    }
}
