import VyronModelDomain

enum VyronDevelopmentTaskTool {
    static let name = VyronDevelopmentToolName.readTask
    static let definition = DevelopmentExternalTool(
        name: name,
        description: "Read one complete page of the original submitted task. Read all pages before other tools or completion.",
        inputSchema: [
            "type": .string("object"), "additionalProperties": .bool(false),
            "properties": .object(["page": .object(["type": .string("integer"), "minimum": .number(0)])]),
            "required": .array([.string("page")])
        ],
        isReadOnly: true
    )
}
