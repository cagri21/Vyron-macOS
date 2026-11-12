import CryptoKit
import Foundation

struct VyronDevelopmentRunControl {
    private var observedOutcomes: Set<String> = []
    private(set) var stagnantRounds = 0
    private(set) var progressVersion = 0
    private(set) var stalledTools: [String] = []
    private var roundAdvanced = false

    static func callKey(_ call: DevelopmentToolCall) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(call.function)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    mutating func observe(_ call: DevelopmentToolCall, response: String) throws {
        // Object field order is transport detail, not progress. Native outcomes are JSON.
        let value = try JSONDecoder().decode(DevelopmentJSONValue.self, from: Data(response.utf8))
        let tool = call.function.name
        guard case .object(let fields) = value,
            fields["ok"] == .bool(true),
            !Self.isUnchangedOutcome(fields),
            tool != VyronDevelopmentPlanTool.name,
            tool != VyronDevelopmentResumeTool.name else {
            recordStalledTool(tool)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        // Varying a list limit or search query without learning anything new is not progress.
        let identity = ["list_files", "search"].contains(tool) ? tool : try Self.callKey(call)
        if observedOutcomes.insert(identity + digest).inserted {
            recordProgress()
        } else {
            recordStalledTool(tool)
        }
    }

    mutating func recordProgress() {
        roundAdvanced = true
        progressVersion += 1
    }

    mutating func appliedGuidance() {
        observedOutcomes.removeAll()
        stagnantRounds = 0
        recordProgress()
    }

    mutating func finishRound() {
        stagnantRounds = roundAdvanced ? 0 : stagnantRounds + 1
        if roundAdvanced { stalledTools.removeAll() }
        roundAdvanced = false
    }

    var shouldReplan: Bool { stagnantRounds >= 1 }
    var shouldStop: Bool { stagnantRounds >= VyronDevelopmentRunLimits.stagnantRounds }

    private mutating func recordStalledTool(_ tool: String) {
        if !stalledTools.contains(tool) { stalledTools.append(tool) }
    }

    private static func isUnchangedOutcome(_ fields: [String: DevelopmentJSONValue]) -> Bool {
        guard case .string(let output) = fields["output"] else { return false }
        return [
            "Already matches ", "The replacement is unchanged;", "Previously attempted"
        ].contains { output.hasPrefix($0) }
    }
}
