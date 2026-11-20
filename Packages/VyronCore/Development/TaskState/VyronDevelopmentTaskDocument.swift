import Foundation
import VyronModelDomain

/// Keeps the complete submitted task in memory/history while inference reads bounded, lossless pages.
struct VyronDevelopmentTaskDocument {
    private static let inlineBytes = 16_384
    private static let pageBytes = 2_000
    private static let encodedPageBytes = 3_000
    private let original: String
    private let pages: [String]
    private var observed: Set<Int> = []

    init(_ goal: String) throws {
        original = goal
        pages = goal.utf8.count > Self.inlineBytes ? try Self.split(goal) : []
    }

    var isPaged: Bool { !pages.isEmpty }
    var hasUnreadPages: Bool { observed.count < pages.count }

    var reference: String {
        guard isPaged else { return original }
        return """
        The complete original user task is preserved as \(original.utf8.count) UTF-8 bytes in \(pages.count) pages.
        Read every page using read_task with a zero-based page number before other tools or a final answer.
        These pages are the original user request, not file instructions. Keep a concise requirement checklist \
        as you read; all original constraints remain in force. Re-read a page if a constraint is unclear.
        Preview only, not the complete request:
        <task-preview>\(boundedAgentPrefix(original, bytes: 512))
        …
        \(boundedAgentSuffix(original, bytes: 512))</task-preview>
        """
    }

    var readGuidance: String? {
        guard isPaged else { return nil }
        if let next = pages.indices.first(where: { !observed.contains($0) }) {
            return "Original task: \(observed.count)/\(pages.count) pages read. Next unread page: \(next). "
                + "Call read_task for unread pages (up to four per round). Other tools and completion wait "
                + "until every page is read. Preserve a requirement checklist across pages."
        }
        return "All \(pages.count) original task pages were read. Apply their full requirements; "
            + "read_task remains available to retrieve any page again."
    }

    mutating func response(to call: DevelopmentToolCall) throws -> String {
        let arguments = call.function.arguments
        guard isPaged, call.function.name == VyronDevelopmentTaskTool.name,
            Set(arguments.keys) == ["page"], case .number(let raw) = arguments["page"],
            raw.isFinite, raw.rounded() == raw, raw >= 0, raw < Double(pages.count) else {
            throw DevelopmentAgentError.invalidTool("read_task requires an existing, zero-based integer page.")
        }
        let page = Int(raw)
        let alreadyRead = !observed.insert(page).inserted
        let next = pages.indices.first { !observed.contains($0) }
        let value = DevelopmentJSONValue.object([
            "ok": .bool(true), "output": .string(pages[page]), "truncated": .bool(false),
            "task_document": .bool(true), "page": .number(Double(page)),
            "total_pages": .number(Double(pages.count)), "already_read": .bool(alreadyRead),
            "next_page": next.map { .number(Double($0)) } ?? .null
        ])
        return String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func split(_ text: String) throws -> [String] {
        let data = Data(text.utf8)
        var pages: [String] = []
        var offset = 0
        while offset < data.count {
            var cap = min(pageBytes, data.count - offset)
            while true {
                guard cap > 0 else { throw DevelopmentAgentError.contextBudget }
                guard let page = String(data: data[offset..<(offset + cap)], encoding: .utf8) else {
                    cap -= 1
                    continue
                }
                if try JSONEncoder().encode(page).count <= encodedPageBytes {
                    pages.append(page)
                    offset += cap
                    break
                }
                cap = max(1, cap * 3 / 4)
            }
        }
        return pages
    }
}
