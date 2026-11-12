import Foundation

/// Safe failure metadata: never retains NSError descriptions, userInfo, or image contents.
public struct VyronImageTextRecognitionFailure: Error, LocalizedError, Sendable, Equatable {
    public let domain: String
    public let code: Int
    public let underlying: [VyronImageTextFailureDiagnostic]

    public init(error: any Error) {
        let source = error as NSError
        domain = source.domain
        code = source.code
        var diagnostics: [VyronImageTextFailureDiagnostic] = []
        var current = source.userInfo[NSUnderlyingErrorKey] as? NSError
        while let nested = current, diagnostics.count < VyronImageTextLimits.maximumFailureDiagnosticCount - 1 {
            diagnostics.append(VyronImageTextFailureDiagnostic(domain: nested.domain, code: nested.code))
            current = nested.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        underlying = diagnostics
    }

    public var errorDescription: String? {
        VyronImageTextError.recognitionFailed.errorDescription
    }
}
