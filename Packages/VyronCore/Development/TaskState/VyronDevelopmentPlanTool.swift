import Foundation
import VyronModelDomain

enum VyronDevelopmentPlanTool {
    static let name = VyronDevelopmentToolName.updatePlan

    static func decode(_ call: DevelopmentToolCall) throws -> VyronDevelopmentPlanUpdate {
        guard call.function.name == name,
            Set(call.function.arguments.keys).isSubset(of: ["plan", "explanation"]),
            case .array(let values) = call.function.arguments["plan"],
            (1...VyronDevelopmentTaskLimits.maximumPlanSteps).contains(values.count)
        else { throw invalid() }
        let steps = try values.map { value -> VyronDevelopmentPlanStep in
            guard case .object(let fields) = value,
                Set(fields.keys) == ["step", "status"],
                case .string(let title) = fields["step"],
                case .string(let rawStatus) = fields["status"],
                let status = VyronDevelopmentPlanStepStatus(rawValue: rawStatus)
            else { throw invalid() }
            return VyronDevelopmentPlanStep(title: title.trimmingCharacters(in: .whitespacesAndNewlines), status: status)
        }
        let explanation: String?
        if let value = call.function.arguments["explanation"] {
            guard case .string(let text) = value,
                VyronDevelopmentTaskText.isValid(
                    text, maximumBytes: VyronDevelopmentTaskLimits.maximumSummaryBytes, permitsEmpty: true
                )
            else { throw invalid() }
            explanation = text
        } else {
            explanation = nil
        }
        do { try VyronDevelopmentTaskState.validatePlan(steps) }
        catch { throw invalid() }
        return VyronDevelopmentPlanUpdate(steps: steps, explanation: explanation)
    }

    private static func invalid() -> DevelopmentAgentError {
        .invalidTool("Provide one to twelve distinct plan steps with pending, in_progress, or completed status; at most one may be in progress.")
    }
}
