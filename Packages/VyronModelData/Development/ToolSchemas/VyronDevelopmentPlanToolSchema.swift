import Foundation
import VyronModelDomain

package enum VyronDevelopmentPlanToolSchema {
    static let name = VyronDevelopmentToolName.updatePlan

    package static let definition = DevelopmentExternalTool(
        name: name,
        description:
            "Save or update the current task's staged implementation plan. Use one to twelve meaningful steps, at most one in progress, and mark a step completed only after its actual work and verification are done. This records progress; it does not execute files, commands, or integrations.",
        inputSchema: [
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "required": .array([.string("plan")]),
            "properties": .object([
                "explanation": .object([
                    "type": .string("string"),
                    "description": .string("A brief reason for this plan update; at most 1,024 UTF-8 bytes."),
                    "maxLength": .number(1_024)
                ]),
                "plan": .object([
                    "type": .string("array"),
                    "minItems": .number(1),
                    "maxItems": .number(Double(VyronDevelopmentTaskLimits.maximumPlanSteps)),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "required": .array([.string("step"), .string("status")]),
                        "properties": .object([
                            "step": .object([
                                "type": .string("string"),
                                "description": .string("A distinct meaningful stage, at most 512 UTF-8 bytes."),
                                "minLength": .number(1),
                                "maxLength": .number(512)
                            ]),
                            "status": .object([
                                "type": .string("string"),
                                "enum": .array([.string("pending"), .string("in_progress"), .string("completed")])
                            ])
                        ])
                    ])
                ])
            ])
        ],
        isReadOnly: true
    )
}
