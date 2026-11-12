import Combine
import Foundation
import VyronCore

@MainActor
final class VyronConversationInteractions: ObservableObject {
    @Published private(set) var pendingUserInput: VyronUserInputRequest? {
        didSet {
            if pendingUserInput?.id != oldValue?.id {
                userInputObservedAt = pendingUserInput == nil ? nil : Date()
            }
        }
    }
    @Published private(set) var pendingCommandApproval: CommandApproval? {
        didSet {
            if pendingCommandApproval?.id != oldValue?.id {
                commandObservedAt = pendingCommandApproval == nil ? nil : Date()
            }
        }
    }
    @Published var showCommandApproval = false
    @Published private(set) var projectApprovalMode: VyronProjectApprovalMode

    private(set) var userInputGeneration: UUID?
    private(set) var userInputConversationID: UUID?
    private(set) var approvalGeneration: UUID?
    private(set) var userInputObservedAt: Date?
    private(set) var commandObservedAt: Date?
    private var userInputContinuation: CheckedContinuation<VyronUserInputResponse, any Error>?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var userInputWaiterID: UUID?
    private var approvalWaiterID: UUID?
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
        let saved = defaults.string(forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue) ?? ""
        projectApprovalMode = VyronProjectApprovalMode(rawValue: saved) ?? .approveForMe
    }

    func selectProjectApprovalMode(_ mode: VyronProjectApprovalMode) {
        guard mode != projectApprovalMode else { return }
        projectApprovalMode = mode
        defaults.set(mode.rawValue, forKey: VyronUserDefaultsKey.projectCommandApprovalMode.rawValue)
    }

    func requestUserInput(
        _ request: VyronUserInputRequest,
        generationID: UUID,
        conversation: () -> UUID?,
        didPresent: () -> Void
    ) async throws -> VyronUserInputResponse {
        try Task.checkCancellation()
        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled, let conversationID = conversation() else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                cancelPendingUserInput()
                userInputContinuation = continuation
                userInputWaiterID = waiterID
                userInputGeneration = generationID
                userInputConversationID = conversationID
                pendingUserInput = request
                didPresent()
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.userInputWaiterID == waiterID else { return }
                self.cancelPendingUserInput()
            }
        }
    }

    func respondToUserInput(
        _ response: VyronUserInputResponse,
        conversationID: UUID?,
        canRespond: (UUID) -> Bool,
        record: (VyronUserInputRequest) -> Void
    ) -> Bool {
        guard let request = pendingUserInput, request.id == response.requestID,
            let generationID = userInputGeneration, canRespond(generationID),
            userInputConversationID == conversationID,
            response.answers.count == request.questions.count,
            Set(response.answers.map(\.questionID)) == Set(request.questions.map(\.id)),
            response.answers.allSatisfy({
                !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && $0.value.utf8.count <= VyronUserInputLimits.maximumAnswerBytes
            })
        else { return false }
        record(request)
        let continuation = takeUserInputContinuation()
        continuation?.resume(returning: response)
        return true
    }

    func cancelPendingUserInput() {
        let continuation = takeUserInputContinuation()
        continuation?.resume(throwing: CancellationError())
    }

    private func takeUserInputContinuation() -> CheckedContinuation<VyronUserInputResponse, any Error>? {
        let continuation = userInputContinuation
        userInputContinuation = nil
        userInputWaiterID = nil
        userInputGeneration = nil
        userInputConversationID = nil
        pendingUserInput = nil
        return continuation
    }

    func reviewCommand(
        _ approval: CommandApproval,
        generationID: UUID,
        canPresent: () -> Bool,
        willPresent: () -> Void
    ) async -> Bool {
        guard !Task.isCancelled else { return false }
        let waiterID = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled, canPresent() else {
                    continuation.resume(returning: false)
                    return
                }
                approvalContinuation?.resume(returning: false)
                approvalContinuation = continuation
                approvalWaiterID = waiterID
                approvalGeneration = generationID
                pendingCommandApproval = approval
                willPresent()
                showCommandApproval = true
            }
        } onCancel: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.approvalWaiterID == waiterID else { return }
                self.respondToCommandApproval(false)
            }
        }
    }

    func respondToCommandApproval(_ approved: Bool, approvalID: UUID? = nil) {
        if let approvalID, pendingCommandApproval?.id != approvalID { return }
        let continuation = approvalContinuation
        approvalContinuation = nil
        approvalWaiterID = nil
        approvalGeneration = nil
        pendingCommandApproval = nil
        showCommandApproval = false
        continuation?.resume(returning: approved)
    }
}
