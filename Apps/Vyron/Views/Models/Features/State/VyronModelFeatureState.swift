import Combine
import Foundation
import VyronModelDomain

@MainActor
final class VyronModelFeatureState: ObservableObject {
    @Published private(set) var toolChecks: [VyronModelToolCheck] = []
    @Published private(set) var thinkingChecks: [VyronModelThinkingCheck] = []
    @Published private(set) var isVerifying = false
    private(set) var verificationTask: Task<Void, Never>?
    private var verificationID: UUID?

    func startVerification(_ operation: @escaping @MainActor () async -> Void) {
        let requestID = UUID()
        verificationID = requestID
        isVerifying = true
        verificationTask = Task { @MainActor [weak self] in
            defer { self?.finishVerification(requestID) }
            await operation()
        }
    }

    @discardableResult
    func cancelVerification() -> Task<Void, Never>? {
        let task = verificationTask
        verificationID = nil
        task?.cancel()
        verificationTask = nil
        isVerifying = false
        return task
    }

    func removeChecks(for connectionID: UUID) {
        toolChecks.removeAll { $0.selection.connection?.id == connectionID }
        thinkingChecks.removeAll { $0.selection.connection?.id == connectionID }
    }

    func removeChecks(for selection: VyronModelFeatureSelection) {
        toolChecks.removeAll { $0.selection == selection }
        thinkingChecks.removeAll { $0.selection == selection }
    }

    func record(_ result: VyronNativeToolVerification, for selection: VyronModelFeatureSelection) {
        toolChecks.removeAll { $0.selection == selection }
        toolChecks.append(VyronModelToolCheck(selection: selection, result: result))
    }

    func rejectsLocalNativeTools(for model: String, revision: UUID) -> Bool {
        toolChecks.contains {
            $0.selection.connection == nil && $0.selection.modelName == model
                && $0.selection.revision == revision && $0.result == .unsupported
        }
    }

    func record(_ support: VyronModelThinkingSupport, for selection: VyronModelFeatureSelection) {
        thinkingChecks.removeAll { $0.selection == selection }
        thinkingChecks.append(VyronModelThinkingCheck(selection: selection, support: support))
    }

    private func finishVerification(_ requestID: UUID) {
        guard verificationID == requestID else { return }
        isVerifying = false
        verificationTask = nil
        verificationID = nil
    }
}
