import Foundation
import VyronAutomation
import VyronCore

extension VyronMacWorkSession {
    func openApplication(_ call: DevelopmentToolCall) async throws -> DevelopmentExternalResult {
        try requireArguments(call, keys: ["application_id"])
        let id = try applicationID(call)
        guard let app = dependencies.controller.availableApplications().first(where: { $0.id == id }) else {
            throw argumentError()
        }
        _ = try await authorize(call, application: app, element: nil)
        try validateCurrent()
        guard dependencies.controller.availableApplications().contains(app) else { throw argumentError() }
        let running: DesktopApplication
        if app.processIdentifier > 0 {
            running = try runningApplication(id: app.id)
            guard running.processIdentifier == app.processIdentifier else { throw argumentError() }
            try dependencies.controller.activate(application: running)
        } else {
            running = try await dependencies.controller.launch(applicationID: app.id)
        }
        try validateCurrent()
        guard running.id == app.id else { throw argumentError() }
        snapshots.removeValue(forKey: app.id)
        return try result([
            "application_id": .string(running.id), "name": .string(running.name),
            "message": .string("The application was opened or focused. Inspect its actual state next; this does "
                + "not establish a simulator boot or project launch.")
        ])
    }

    func openProject(_ call: DevelopmentToolCall) async throws -> DevelopmentExternalResult {
        try requireArguments(call, keys: ["path"])
        let path = try string("path", in: call)
        let url = try VyronMacWorkProject.resolve(path: path, root: currentProjectRoot)
        guard let xcode = dependencies.controller.availableApplications().first(where: {
            $0.id == VyronMacWorkApplicationIDs.xcode
        })
        else { throw VyronMacWorkError(message: "Installed Xcode is unavailable in the native application catalog.") }
        _ = try await authorize(call, application: xcode, element: nil)
        try validateCurrent()
        guard try VyronMacWorkProject.resolve(path: path, root: currentProjectRoot) == url else {
            throw argumentError()
        }
        let running = try await dependencies.controller.openProject(url)
        try validateCurrent()
        guard running.id == xcode.id else { throw argumentError() }
        snapshots.removeValue(forKey: xcode.id)
        return try result([
            "application_id": .string(running.id), "path": .string(path),
            "message": .string("The project was opened in Xcode. Inspect Xcode's actual windows and menu bar, "
                + "choose the requested simulator destination, then use its Product > Run control. "
                + "Verify build and launch results from the visible app or captured screenshot.")
        ])
    }

    func controlApplication(_ call: DevelopmentToolCall) async throws -> DevelopmentExternalResult {
        var keys: Set<String> = ["application_id", "snapshot_id"]
        if call.function.name == VyronMacWorkTools.pressKey { keys.insert("key") } else { keys.insert("element_id") }
        if call.function.name == VyronMacWorkTools.typeText { keys.insert("text") }
        try requireArguments(call, keys: keys)
        if call.function.name == VyronMacWorkTools.typeText { _ = try string("text", in: call) }
        if call.function.name == VyronMacWorkTools.pressKey { _ = try string("key", in: call) }
        let selection = try target(call)
        let record = try snapshot(for: selection)
        let info = try element(for: selection)
        let reviewed = try await authorize(call, application: record.application, element: info)
        _ = try snapshot(for: selection)
        try dependencies.controller.activate(application: record.application)
        try await Task.sleep(for: .milliseconds(150))
        try validateCurrent()
        _ = try snapshot(for: selection)
        let currentInfo = try element(for: selection)
        guard currentInfo == info else { throw argumentError() }
        switch policy(call, application: record.application, element: currentInfo) {
        case .refused(let reason): throw VyronMacWorkError(message: reason)
        case .review where !reviewed:
            throw VyronMacWorkError(message: "The native target changed and requires a new inspection and review.")
        default: break
        }
        var feedback: VyronComputerActionFeedback?
        switch call.function.name {
        case VyronMacWorkTools.click, VyronMacWorkTools.typeText:
            guard let id = selection.elementID else { throw argumentError() }
            let frame = try dependencies.controller.elementFrame(elementID: id, snapshotID: selection.snapshotID)
            let title: String
            if call.function.name == VyronMacWorkTools.click {
                try dependencies.controller.click(elementID: id, snapshotID: selection.snapshotID)
                title = VyronControlText.actionClick
            } else {
                try dependencies.controller.typeText(
                    try string("text", in: call), elementID: id, snapshotID: selection.snapshotID
                )
                title = VyronControlText.actionType
            }
            if let frame, VyronComputerPointerGeometry.isUsable(frame) {
                feedback = .init(title: title, applicationID: selection.applicationID, targetFrame: frame)
            }
        case VyronMacWorkTools.pressKey:
            let current = try dependencies.controller.inspect(application: record.application)
            guard current.text == record.observation.text else {
                throw VyronMacWorkError(message: "The app's visible controls changed after inspection. Inspect again "
                    + "before sending a keyboard action.")
            }
            try dependencies.controller.pressKey(try string("key", in: call), application: record.application)
        default: throw argumentError()
        }
        snapshots.removeValue(forKey: selection.applicationID)
        try validateCurrent()
        if let feedback { dependencies.onTargetAction(feedback) }
        return try result([
            "application_id": .string(selection.applicationID),
            "message": .string("The native action was sent. Its prior snapshot is now invalid. Inspect the "
                + "application or capture its window to verify the actual result before continuing.")
        ])
    }
}
