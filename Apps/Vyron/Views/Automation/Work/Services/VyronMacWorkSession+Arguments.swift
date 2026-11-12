import Foundation
import VyronAutomation
import VyronCore

extension VyronMacWorkSession {
    func requireArguments(_ call: DevelopmentToolCall, keys: Set<String>) throws {
        guard Set(call.function.arguments.keys) == keys else { throw argumentError() }
    }

    func argumentError() -> VyronMacWorkError {
        VyronMacWorkError(message: "Use the exact native Mac tool fields and IDs returned by this response's "
            + "app list and inspection. Arbitrary code, shell commands and extra fields are unavailable.")
    }

    func string(_ name: String, in call: DevelopmentToolCall) throws -> String {
        guard case .string(let value) = call.function.arguments[name], !value.isEmpty,
            value.utf8.count <= 12_000, !value.contains("\0") else { throw argumentError() }
        return value
    }

    func applicationID(_ call: DevelopmentToolCall) throws -> String {
        let value = try string("application_id", in: call)
        guard value.utf8.count <= 200 else { throw argumentError() }
        return value
    }

    func optionalString(_ name: String, in call: DevelopmentToolCall) -> String? {
        guard case .string(let value) = call.function.arguments[name] else { return nil }
        return value
    }

    func target(_ call: DevelopmentToolCall) throws -> VyronMacWorkTarget {
        let appID = try applicationID(call)
        guard let snapshotID = UUID(uuidString: try string("snapshot_id", in: call)) else { throw argumentError() }
        var elementID: Int?
        if call.function.name != VyronMacWorkTools.pressKey {
            guard case .number(let number) = call.function.arguments["element_id"], number.isFinite,
                number.rounded() == number, (1...Double(Int32.max)).contains(number) else { throw argumentError() }
            elementID = Int(number)
        }
        return VyronMacWorkTarget(applicationID: appID, snapshotID: snapshotID, elementID: elementID)
    }

    func snapshot(for target: VyronMacWorkTarget) throws -> VyronMacWorkSnapshot {
        try validateCurrent()
        let app = try runningApplication(id: target.applicationID)
        guard let record = snapshots[target.applicationID], record.observation.id == target.snapshotID,
            record.application.processIdentifier == app.processIdentifier,
            record.application.bundleIdentifier == app.bundleIdentifier,
            (0...maximumSnapshotAge).contains(Date().timeIntervalSince(record.observation.capturedAt))
        else {
            throw VyronMacWorkError(message: "The native inspection is stale, belongs to another app, or the app "
                + "restarted. Inspect this application again before acting.")
        }
        return record
    }

    func element(for target: VyronMacWorkTarget) throws -> NativeElementInfo? {
        guard let elementID = target.elementID else { return nil }
        let info = try dependencies.controller.elementInfo(elementID: elementID, snapshotID: target.snapshotID)
        guard info.applicationID == target.applicationID, info.elementID == elementID else { throw argumentError() }
        return info
    }
}
