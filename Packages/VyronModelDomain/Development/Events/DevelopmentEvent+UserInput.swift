import Foundation

extension DevelopmentEvent {
    public var isUserInput: Bool { tool == VyronDevelopmentToolName.requestUserInput }
}
