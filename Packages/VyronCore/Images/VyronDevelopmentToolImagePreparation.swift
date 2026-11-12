import Foundation

/// Keeps screenshot tools usable for known text-only models without changing manual attachment behavior.
actor VyronDevelopmentToolImagePreparation {
    private let textPreparation: VyronImageTextPreparation
    private static let textOnlyContext = """
    The selected model does not advertise vision. Screenshot pixels are not supplied to it. Only locally \
    recognized text is available; layout, colors, objects, and other visual details were not analyzed. \
    Do not claim visual inspection from this text. The captured screenshot remains available as an artifact.
    """

    init(recognizer: any VyronImageTextRecognizing = VyronAppleVisionTextRecognizer()) {
        textPreparation = VyronImageTextPreparation(recognizer: recognizer)
    }

    func observation(
        tool: String, images: [VyronImageAttachment], capabilities: [String]?
    ) async throws -> DevelopmentMessage? {
        try Task.checkCancellation()
        guard let pixels = try VyronDevelopmentToolImageContext.observation(tool: tool, images: images) else {
            return nil
        }
        guard let capabilities, !capabilities.isEmpty, !capabilities.contains("vision") else { return pixels }
        let evidence: String
        do {
            let prepared = try await textPreparation.chatMessages([
                ChatMessage(role: "user", content: "", images: images)
            ])
            try Task.checkCancellation()
            evidence = Self.textOnlyContext + "\n" + (prepared.first?.content ?? "No OCR evidence was returned.")
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                throw CancellationError()
            }
            evidence = Self.textOnlyContext + "\n" + Self.unavailableEvidence(error)
        }
        try Task.checkCancellation()
        return DevelopmentMessage(
            observation: VyronDevelopmentImageObservation(tool: tool, textEvidence: evidence),
            images: []
        )
    }

    private static func unavailableEvidence(_ error: any Error) -> String {
        if let failure = error as? VyronImageTextError {
            switch failure {
            case .noText:
                return "Local OCR found no readable text. No image evidence is available to this model."
            case .textTooLong:
                return "Local OCR exceeded the bounded text limit. No image evidence is available to this model."
            case .recognitionFailed:
                return "Local OCR failed. No image evidence is available to this model."
            }
        }
        if let failure = error as? VyronImageTextRecognitionFailure {
            return "Local OCR failed (domain: \(boundedAgentPrefix(failure.domain, bytes: 160)), "
                + "code: \(failure.code)). No image evidence is available to this model."
        }
        return "Local OCR could not provide usable text. No image evidence is available to this model."
    }
}
