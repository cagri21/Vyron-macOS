import Foundation

public enum VyronAssistantRequestKind: Sendable, Equatable {
    case standard
    case webSearch
    case websiteAnalysis
    case computerTask

    public var usesWebEvidence: Bool { self == .webSearch || self == .websiteAnalysis }
}
