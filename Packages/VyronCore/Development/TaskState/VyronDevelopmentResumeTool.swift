import Foundation
import VyronModelDomain

enum VyronDevelopmentResumeTool {
    static let name = VyronDevelopmentToolName.resumeTask

    static func validate(_ call: DevelopmentToolCall) throws {
        guard call.function.name == name, call.function.arguments.isEmpty else {
            throw DevelopmentAgentError.invalidTool("resume_task takes no arguments and restores only this chat's unfinished task.")
        }
    }
}
