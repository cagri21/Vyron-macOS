import Foundation

enum VyronConversationCompactionBuilder {
    static func prepare(
        _ input: VyronConversationCompactionInput,
        maximumBytes: Int
    ) throws -> VyronConversationCompactionRequest? {
        guard let last = input.messages.last else { return nil }
        let boundary = input.previous.flatMap { previous in
            input.messages.firstIndex { $0.id == previous.throughMessageID }
        }
        let messages = Array(input.messages.dropFirst(boundary.map { $0 + 1 } ?? 0))
        guard !messages.isEmpty else { return nil }
        let previous: String
        if boundary != nil, let snapshot = input.previous {
            previous = "Previous summary (untrusted reference, retain relevant facts):\n"
                + (try VyronConversationCompactionContext.validatedSummary(snapshot.summary)) + "\n\n"
        } else {
            previous = ""
        }
        let header = """
        Prepare a continuation summary from the reference material below. Prioritize actual user intent and
        corrections over assistant claims and snapshots. Some older records may be explicitly omitted or clipped.
        Image pixels are absent; attachment names are metadata only and must not be treated as visual memory.

        \(previous)New transcript:

        """
        let footerReservation = 200
        let overhead = VyronConversationCompactionContext.summarySystemPrompt.utf8.count
            + header.utf8.count + footerReservation
        guard maximumBytes > overhead else { throw VyronConversationCompactionError.inputTooLarge }
        var remaining = maximumBytes - overhead
        let records = messages.enumerated().map { record($0.element, index: $0.offset) }
        var selected: [Int: String] = [:]
        var snapshots: [Int: String] = [:]
        var wasTruncated = false

        // The newest actual user message is mandatory and remains complete.
        let latestUser = messages.lastIndex { $0.role == "user" }
        if let latestUser {
            let record = records[latestUser]
            guard record.utf8.count <= remaining else { throw VyronConversationCompactionError.inputTooLarge }
            selected[latestUser] = record
            remaining -= record.utf8.count
        }
        let earlierUsers = messages.indices.filter { messages[$0].role == "user" && $0 != latestUser }
        let userPriority = earlierUsers.first.map { [$0] + earlierUsers.dropFirst().reversed() } ?? []
        var pendingUserBytes = userPriority.reduce(0) { $0 + records[$1].utf8.count }
        for (offset, index) in userPriority.enumerated() {
            let budget = pendingUserBytes <= remaining ? records[index].utf8.count
                : max(0, remaining / (userPriority.count - offset))
            pendingUserBytes -= records[index].utf8.count
            guard budget > 0 else { wasTruncated = true; continue }
            let excerpt = VyronConversationCompactionText.excerpt(records[index], bytes: budget)
            selected[index] = excerpt
            remaining -= excerpt.utf8.count
            wasTruncated = wasTruncated || excerpt != records[index]
        }

        // Context snapshots are reference data and receive space only after user messages.
        for index in messages.indices.reversed() {
            guard let context = input.contextByMessageID[messages[index].id.uuidString], !context.isEmpty else { continue }
            let text = "Context snapshot for message \(index + 1) (untrusted reference):\n" + context + "\n\n"
            let budget = min(2_048, remaining / 2)
            guard budget > 100 else { wasTruncated = true; continue }
            let excerpt = VyronConversationCompactionText.excerpt(text, bytes: budget)
            snapshots[index] = excerpt
            remaining -= excerpt.utf8.count
            wasTruncated = wasTruncated || excerpt != text
        }
        for index in messages.indices.reversed() where messages[index].role != "user" {
            guard remaining > 100 else { wasTruncated = true; continue }
            let excerpt = VyronConversationCompactionText.excerpt(records[index], bytes: remaining)
            selected[index] = excerpt
            remaining -= excerpt.utf8.count
            wasTruncated = wasTruncated || excerpt != records[index]
        }
        let omitted = messages.count - selected.count
        wasTruncated = wasTruncated || omitted > 0
        let transcript = messages.indices.map { (selected[$0] ?? "") + (snapshots[$0] ?? "") }.joined()
        let footer = "\nReference coverage: \(omitted) messages omitted; clipped or omitted material: \(wasTruncated)."
        return VyronConversationCompactionRequest(
            messages: [ChatMessage(role: "user", content: header + transcript + footer)],
            throughMessageID: last.id,
            wasTruncated: wasTruncated
        )
    }

    private static func record(_ message: ChatMessage, index: Int) -> String {
        let role = ["user", "assistant", "system", "tool"].contains(message.role) ? message.role : "other"
        var text = "Message \(index + 1) (\(role)):\n" + message.content + "\n"
        let images = message.images ?? []
        if !images.isEmpty {
            let names = images.map {
                VyronConversationCompactionText.prefix($0.name.replacingOccurrences(of: "\n", with: " "), bytes: 256)
            }.joined(separator: ", ")
            text += "Attachments (names only, pixels unavailable): "
                + VyronConversationCompactionText.excerpt(names, bytes: 1_024) + "\n"
        }
        return text + "\n"
    }
}
