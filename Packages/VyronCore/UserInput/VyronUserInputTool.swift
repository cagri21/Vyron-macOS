import Foundation
import VyronModelData

enum VyronUserInputTool {
    static let name = VyronUserInputToolName.value

    static func decode(_ call: DevelopmentToolCall) throws -> VyronUserInputRequest {
        guard call.function.name == name,
            Set(call.function.arguments.keys) == ["questions"],
            case .array(let values) = call.function.arguments["questions"],
            (1...VyronUserInputLimits.maximumQuestions).contains(values.count)
        else { throw invalidRequest() }
        let questions = try values.map { value in
            guard case .object(let object) = value,
                Set(object.keys).isSubset(of: ["id", "question", "options"]),
                let id = text(object["id"], maximumBytes: VyronUserInputLimits.maximumQuestionIDBytes),
                let question = text(object["question"], maximumBytes: VyronUserInputLimits.maximumQuestionBytes)
            else { throw invalidRequest() }
            let options: [VyronUserInputOption]
            if let rawOptions = object["options"] {
                guard case .array(let values) = rawOptions,
                    values.isEmpty || (2...3).contains(values.count)
                else { throw invalidRequest() }
                options = try values.map { value in
                    guard case .object(let option) = value,
                        Set(option.keys) == ["label", "description"],
                        let label = text(option["label"], maximumBytes: VyronUserInputLimits.maximumOptionLabelBytes),
                        let description = text(
                            option["description"], maximumBytes: VyronUserInputLimits.maximumOptionDescriptionBytes
                        )
                    else { throw invalidRequest() }
                    return VyronUserInputOption(label: label, description: description)
                }
            } else {
                options = []
            }
            guard Set(options.map(\.label)).count == options.count else { throw invalidRequest() }
            return VyronUserInputQuestion(id: id, question: question, options: options)
        }
        guard Set(questions.map(\.id)).count == questions.count,
            try JSONEncoder().encode(questions).count <= VyronUserInputLimits.maximumRequestBytes
        else { throw invalidRequest() }
        return VyronUserInputRequest(questions: questions)
    }

    static func validate(_ response: VyronUserInputResponse, for request: VyronUserInputRequest) throws {
        guard response.requestID == request.id,
            response.answers.count == request.questions.count,
            Set(response.answers.map(\.questionID)) == Set(request.questions.map(\.id)),
            response.answers.allSatisfy({
                text(.string($0.value), maximumBytes: VyronUserInputLimits.maximumAnswerBytes) != nil
            })
        else {
            throw DevelopmentAgentError.invalidTool("The answer does not match the pending questions.")
        }
    }

    static func answerContext(request: VyronUserInputRequest, response: VyronUserInputResponse) throws -> String {
        let answers = Dictionary(uniqueKeysWithValues: response.answers.map { ($0.questionID, $0.value) })
        let entries = request.questions.map { question in
            ["question": question.question, "answer": answers[question.id] ?? ""]
        }
        let json = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self)
        return "The user answered the requested clarifications (JSON conversation data):\n" + json
    }

    private static func text(_ value: DevelopmentJSONValue?, maximumBytes: Int) -> String? {
        guard case .string(let string) = value,
            !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            string.utf8.count <= maximumBytes,
            !string.unicodeScalars.contains(where: { $0.value == 0 })
        else { return nil }
        return string
    }

    private static func invalidRequest() -> DevelopmentAgentError {
        .invalidTool("Ask one to three questions with unique IDs and either no options or two to three choices.")
    }
}
