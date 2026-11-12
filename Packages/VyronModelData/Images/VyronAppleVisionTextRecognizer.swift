import Foundation
import Vision
import VyronModelDomain

/// Vision executes on the device. No image or extracted text is uploaded by this adapter.
public actor VyronAppleVisionTextRecognizer: VyronImageTextRecognizing {
    public init() {}

    public func recognizeText(in image: VyronImageAttachment) async throws -> String {
        try Task.checkCancellation()
        try VyronImageAttachment.validate(messages: [ChatMessage(role: "user", content: "", images: [image])])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(data: image.data, options: [:])
        do {
            try handler.perform([request])
        } catch {
            try Task.checkCancellation()
            throw VyronImageTextRecognitionFailure(error: error)
        }
        // A cancelled caller never receives or sends a result after Vision's synchronous work finishes.
        try Task.checkCancellation()
        var lines: [String] = []
        var textBytes = 0
        for observation in request.results ?? [] {
            try Task.checkCancellation()
            guard let candidate = observation.topCandidates(1).first else { continue }
            textBytes += candidate.string.utf8.count + (lines.isEmpty ? 0 : 1)
            guard textBytes <= VyronImageTextLimits.maximumImageTextBytes else {
                throw VyronImageTextError.textTooLong
            }
            lines.append(candidate.string)
        }
        return lines.joined(separator: "\n")
    }
}
