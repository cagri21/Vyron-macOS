import Foundation
import VyronCore

struct VyronUserInputDraft {
    private var answers: [VyronUserInputAnswer] = []

    func value(for questionID: String) -> String {
        answers.first { $0.questionID == questionID }?.value ?? ""
    }

    mutating func setValue(_ value: String, for questionID: String) {
        answers.removeAll { $0.questionID == questionID }
        answers.append(VyronUserInputAnswer(questionID: questionID, value: value))
    }

    func response(to request: VyronUserInputRequest) -> VyronUserInputResponse? {
        let ordered = request.questions.map { question in
            VyronUserInputAnswer(
                questionID: question.id,
                value: value(for: question.id).trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        guard !ordered.isEmpty, ordered.allSatisfy({
            !$0.value.isEmpty && $0.value.utf8.count <= VyronUserInputLimits.maximumAnswerBytes
        }) else {
            return nil
        }
        return VyronUserInputResponse(requestID: request.id, answers: ordered)
    }

    func responseSkippingUnanswered(
        to request: VyronUserInputRequest,
        skippedAnswer: String
    ) -> VyronUserInputResponse? {
        var completed = self
        for question in request.questions where value(for: question.id)
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completed.setValue(skippedAnswer, for: question.id)
        }
        return completed.response(to: request)
    }
}
