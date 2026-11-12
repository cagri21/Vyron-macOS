import Foundation
import VyronModelDomain

enum VyronDevelopmentResumeToolSchema {
    static let name = VyronDevelopmentToolName.resumeTask

    static let definition = DevelopmentExternalTool(
        name: name,
        description: "Restore the saved unfinished task for this chat when the current user asks to continue it. "
            + "Restores its original goal, stages, user guidance and recorded outcomes without executing any action. "
            + "The latest user request remains authoritative; never use an old task to expand the current scope.",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false)
        ],
        isReadOnly: true
    )
}
