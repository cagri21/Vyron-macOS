import Foundation
import VyronModelDomain

extension DevelopmentToolDefinition {
    static let userInput = DevelopmentToolDefinition(
        function: .init(
            name: VyronUserInputToolName.value,
            description:
                "Ask the user for a material missing preference or clarification, then continue the same task with their answers. Never use this for permissions or command approval. Use sensible assumptions for routine decisions. Free text is always supported. String limits are UTF-8 byte limits; the entire request must fit 6000 bytes.",
            parameters: .init(schema: [
                "type": .string("object"),
                "additionalProperties": .bool(false),
                "required": .array([.string("questions")]),
                "properties": .object([
                    "questions": .object([
                        "type": .string("array"),
                        "minItems": .number(1),
                        "maxItems": .number(3),
                        "items": .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "required": .array([.string("id"), .string("question")]),
                            "properties": .object([
                                "id": .object([
                                    "type": .string("string"),
                                    "description": .string("A unique question ID within this request."),
                                    "minLength": .number(1),
                                    "maxLength": .number(80)
                                ]),
                                "question": .object([
                                    "type": .string("string"),
                                    "description": .string("One self-contained question in the user's language."),
                                    "minLength": .number(1),
                                    "maxLength": .number(800)
                                ]),
                                "options": .object([
                                    "type": .string("array"),
                                    "description": .string(
                                        "Omit or leave empty for free text; otherwise provide two to three choices, recommended first. Never add an Other option."
                                    ),
                                    "maxItems": .number(3),
                                    "items": .object([
                                        "type": .string("object"),
                                        "additionalProperties": .bool(false),
                                        "required": .array([.string("label"), .string("description")]),
                                        "properties": .object([
                                            "label": .object([
                                                "type": .string("string"),
                                                "minLength": .number(1),
                                                "maxLength": .number(160)
                                            ]),
                                            "description": .object([
                                                "type": .string("string"),
                                                "minLength": .number(1),
                                                "maxLength": .number(400)
                                            ])
                                        ])
                                    ])
                                ])
                            ])
                        ])
                    ])
                ])
            ])
        )
    )
}
