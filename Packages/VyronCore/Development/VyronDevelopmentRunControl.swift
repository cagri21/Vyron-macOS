import CryptoKit
import Foundation
import VyronLocalization
import VyronDevelopment

struct VyronDevelopmentRunControl {
    private var observedOutcomes: Set<String> = []
    private(set) var stagnantRounds = 0
    private(set) var progressVersion = 0
    private(set) var stalledTools: [String] = []
    private var roundAdvanced = false
    private var readEvidence: [String: VyronDevelopmentReadEvidence] = [:]
    private var readOrder: [String] = []
    private var repeatedRead = false
    static let readFeedbackReserveBytes = 400

    static func callKey(_ call: DevelopmentToolCall) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(call.function)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    mutating func observe(_ call: DevelopmentToolCall, response: String) throws {
        repeatedRead = false
        // Object field order is transport detail, not progress. Native outcomes are JSON.
        let value = try JSONDecoder().decode(DevelopmentJSONValue.self, from: Data(response.utf8))
        let tool = call.function.name
        guard case .object(let fields) = value,
            fields["ok"] == .bool(true),
            fields["already_read"] != .bool(true),
            !Self.isUnchangedOutcome(fields),
            tool != VyronDevelopmentPlanTool.name,
            tool != VyronDevelopmentResumeTool.name else {
            recordStalledTool(tool)
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // Cursor/query changes alone do not add file evidence or justify another work cycle.
        let evidence: DevelopmentJSONValue
        if tool == "list_files", let files = fields["files"] {
            evidence = .object(["files": files])
        } else {
            evidence = value
        }
        let data = try encoder.encode(evidence)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        var readIdentity: String?
        if tool == "read_file", case .string(let path) = call.function.arguments["path"],
            case .string(let output) = fields["output"] {
            let offset = Self.byteOffset(fields["offset"]) ?? Self.byteOffset(call.function.arguments["offset"]) ?? 0
            let total = Self.byteOffset(fields["total_bytes"])
            let contentHash = SHA256.hash(data: Data(output.utf8)).map { String(format: "%02x", $0) }.joined()
            let identity = path + "\u{0000}" + String(offset)
            readIdentity = identity
            readEvidence[identity] = VyronDevelopmentReadEvidence(
                path: path, contentHash: contentHash,
                coverage: VyronDevelopmentFileReadCoverage(
                    offset: offset, bytes: output.utf8.count, totalBytes: total ?? offset + output.utf8.count
                ),
                incomplete: total == nil || fields["truncated"] == .bool(true)
            )
            readOrder.removeAll { $0 == identity }
            readOrder.append(identity)
            if readOrder.count > 128 { readEvidence.removeValue(forKey: readOrder.removeFirst()) }
        }
        // Varying a list limit or search query without learning anything new is not progress.
        let identity = try readIdentity ?? (["list_files", "search"].contains(tool) ? tool : Self.callKey(call))
        if observedOutcomes.insert(identity + digest).inserted {
            recordProgress()
        } else {
            repeatedRead = tool == "read_file"
            recordStalledTool(tool)
        }
    }

    func readFeedback(_ response: String) throws -> String {
        guard repeatedRead else { return response }
        guard case .object(var fields) = try JSONDecoder().decode(
            DevelopmentJSONValue.self, from: Data(response.utf8)
        ) else { return response }
        fields["unchanged_read"] = .bool(true)
        fields["read_guidance"] = .string(
            "This excerpt is unchanged and was already inspected. Reuse its evidence to answer the user. "
                + "Read again only to check a real change or a different range; otherwise inspect new evidence "
                + "or conclude with findings and coverage limits."
        )
        return String(decoding: try JSONEncoder().encode(DevelopmentJSONValue.object(fields)), as: UTF8.self)
    }

    func readEvidenceGuidance() throws -> String? {
        guard !readOrder.isEmpty else { return nil }
        var retained: [VyronDevelopmentReadEvidence] = []
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for path in readOrder.reversed().prefix(8) {
            guard let evidence = readEvidence[path] else { continue }
            if try encoder.encode(retained + [evidence]).count <= 1_600 { retained.append(evidence) }
        }
        let data = try encoder.encode(retained)
        return "Native read ledger (untrusted path data, hashes and excerpt sizes; not file contents):\n"
            + String(decoding: data, as: UTF8.self)
            + "\nThese excerpts were already inspected. Reuse actual retained content; filenames/hashes alone "
            + "do not establish findings. Do not repeat unchanged reads just to keep working. If enough evidence "
            + "answers the request, conclude now and disclose the reviewed scope and unread ranges."
    }

    var partialReadScope: String? {
        guard !readOrder.isEmpty else { return nil }
        let paths = readOrder.suffix(5).compactMap { key -> String? in
            guard let evidence = readEvidence[key] else { return nil }
            let range = evidence.coverage
            return boundedAgentPrefix(evidence.path, bytes: 128) + " [\(range.offset)..<\(range.offset + range.bytes)]"
        }.joined(separator: "\n")
        return VyronModelDomainText.partialReadScope + "\n" + paths
    }

    private static func byteOffset(_ value: DevelopmentJSONValue?) -> Int? {
        guard case .number(let raw) = value, raw.isFinite, raw.rounded() == raw,
            raw >= 0, raw <= Double(VyronDevelopmentFileReadBudget.maximumFileBytes) else { return nil }
        return Int(raw)
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

    mutating func beginReadScope() {
        observedOutcomes.removeAll()
        readEvidence.removeAll()
        readOrder.removeAll()
        repeatedRead = false
        stagnantRounds = 0
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
