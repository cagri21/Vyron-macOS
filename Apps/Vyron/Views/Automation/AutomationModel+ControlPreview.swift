import Foundation
import VyronAutomation

extension AutomationModel {
    func restartControlPreview() {
        stopControlPreview()
        guard screenCaptureGranted, let app = selectedApplication, app.processIdentifier > 0 else { return }
        let generation = UUID()
        controlPreviewGeneration = generation
        controlPreviewTask = Task { @MainActor [weak self] in
            defer {
                if let self, controlPreviewGeneration == generation {
                    controlPreviewTask = nil
                    controlPreviewGeneration = nil
                }
            }
            while !Task.isCancelled {
                guard let self, controlPreviewGeneration == generation, selectedApplicationID == app.id else { return }
                do {
                    let preview = try await previewCapture.capturePreview(application: app)
                    try Task.checkCancellation()
                    guard controlPreviewGeneration == generation, selectedApplicationID == app.id else { return }
                    controlPreview = preview
                    controlPreviewMessage = nil
                } catch is CancellationError {
                    return
                } catch {
                    guard controlPreviewGeneration == generation else { return }
                    controlPreview = nil
                    controlPreviewMessage = Self.controlPreviewErrorMessage(error)
                    if let previewError = error as? VyronMacPreviewError,
                        case .permissionRequired = previewError {
                        screenCaptureGranted = false
                        return
                    }
                }
                do {
                    try await Task.sleep(for: VyronComputerPreviewStyle.refreshInterval)
                } catch {
                    return
                }
            }
        }
    }

    func stopControlPreview() {
        controlPreviewGeneration = nil
        controlPreviewTask?.cancel()
        controlPreviewTask = nil
        controlPreview = nil
        controlPreviewMessage = nil
        clearControlFeedback()
    }

    func clearControlFeedback() {
        controlFeedback = nil
        controlOverlay.clear()
    }

    private static func controlPreviewErrorMessage(_ error: any Error) -> String {
        guard let error = error as? VyronMacPreviewError else { return VyronControlText.previewFailed }
        switch error {
        case .permissionRequired: return VyronControlText.previewPermission
        case .applicationUnavailable, .windowUnavailable: return VyronControlText.previewWaiting
        case .encodingFailed: return VyronControlText.previewFailed
        }
    }

    func recordSuccessfulControlAction(_ action: ReviewedMacAction, targetFrame: CGRect?) {
        let feedback: VyronComputerActionFeedback
        switch action {
        case .launch(let app):
            feedback = .init(title: VyronControlText.actionOpen, applicationID: app.id)
        case .activate(let app):
            feedback = .init(title: VyronControlText.actionActivate, applicationID: app.id)
        case .openURL(_, let browser):
            guard let browser else { return }
            feedback = .init(title: VyronControlText.actionNavigate, applicationID: browser.id)
        case .click(let app, _, _):
            feedback = .init(title: VyronControlText.actionClick, applicationID: app.id, targetFrame: targetFrame)
        case .type(let app, _, _, _):
            feedback = .init(title: VyronControlText.actionType, applicationID: app.id, targetFrame: targetFrame)
        case .key(let app, _):
            feedback = .init(title: VyronControlText.actionKey, applicationID: app.id)
        case .inspect(let app):
            feedback = .init(title: VyronControlText.actionInspect, applicationID: app.id)
        }
        controlFeedback = feedback
        controlOverlay.show(title: feedback.title, targetFrame: feedback.targetFrame)
    }
}
