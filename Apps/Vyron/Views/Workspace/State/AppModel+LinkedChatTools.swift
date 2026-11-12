import Foundation
import VyronCore

extension AppModel {
    func linkedChatToolContext(response: VyronResponseIdentity, prompt: String) -> VyronLinkedChatToolContext {
        let snapshots = linkedChatReferenceIDs(in: prompt).compactMap { id -> VyronLinkedChatSnapshot? in
            guard let source = conversations.first(where: { $0.id == id }) else { return nil }
            let newline = VyronTextSeparator.line.rawValue
            let text = source.messages.filter { $0.conversationRole != nil }
                .map { "\($0.role):\(newline)\($0.content)" }
                .joined(separator: VyronTextSeparator.paragraph.rawValue)
            return VyronLinkedChatSnapshot(
                conversationID: id,
                title: VyronConversationRequestContext.bytePrefix(source.title, limit: 120),
                text: text
            )
        }
        return VyronLinkedChatToolContext(response: response, snapshots: snapshots)
    }

    func executeLinkedChatTool(
        _ call: DevelopmentToolCall, context: VyronLinkedChatToolContext
    ) throws -> DevelopmentExternalResult {
        guard ownsInteractiveWorkResponse(context.response) else { throw CancellationError() }
        guard VyronLinkedChatTools.handles(call),
            Set(call.function.arguments.keys).isSubset(of: ["conversation_id", "offset"]),
            case .string(let value) = call.function.arguments["conversation_id"],
            let id = UUID(uuidString: value),
            let source = context.snapshots.first(where: { $0.conversationID == id }),
            conversations.contains(where: { $0.id == id })
        else { return linkedChatToolFailure("Choose a saved chat explicitly linked in the current request.") }
        let offset: Int
        if let argument = call.function.arguments["offset"] {
            guard case .number(let number) = argument, number.isFinite, number.rounded() == number,
                number >= 0, number <= Double(Int32.max)
            else { return linkedChatToolFailure("offset must be a nonnegative integer returned by this tool.") }
            offset = Int(number)
        } else {
            offset = 0
        }
        let scalars = source.text.unicodeScalars
        guard offset <= scalars.count else { return linkedChatToolFailure("The transcript offset is unavailable.") }
        let start = scalars.index(scalars.startIndex, offsetBy: offset)
        var excerpt = Array(scalars[start...].prefix(VyronLinkedChatTools.pageScalars))
        let encoder = JSONEncoder()
        while true {
            let next = offset + excerpt.count
            let page = VyronLinkedChatPage(
                snapshot: VyronLinkedChatSnapshot(
                    conversationID: id, title: source.title, text: String(String.UnicodeScalarView(excerpt))
                ),
                nextOffset: next < scalars.count ? next : nil
            )
            let encoded = try encoder.encode(page)
            if encoded.count <= VyronLinkedChatTools.maximumResultBytes {
                return DevelopmentExternalResult(text: String(decoding: encoded, as: UTF8.self))
            }
            guard !excerpt.isEmpty else { return linkedChatToolFailure("The saved chat title is too large.") }
            excerpt.removeLast(min(50, excerpt.count))
        }
    }

    private func linkedChatToolFailure(_ text: String) -> DevelopmentExternalResult {
        DevelopmentExternalResult(text: text, isError: true)
    }
}
