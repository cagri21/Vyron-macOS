import Foundation
import VyronModelDomain

package func hasUnfencedDevelopmentToolMarkup(_ content: String) -> Bool {
    var fence: String?
    var prose: [String] = []
    for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let current = fence {
            if trimmed.hasPrefix(current) { fence = nil }
            continue
        }
        if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
            fence = String(trimmed.prefix(3))
            continue
        }
        prose.append(line)
    }
    let text = prose.joined(separator: "\n")
    return text.range(of: #"(?m)^\s*<function=[A-Za-z_][A-Za-z0-9_]*>"#, options: .regularExpression) != nil
        || text.range(
            of: #"(?ms)^\s*<tool_call>\s*\{.*?"name"\s*:.*?"arguments"\s*:.*?</tool_call>"#,
            options: .regularExpression
        ) != nil
}
