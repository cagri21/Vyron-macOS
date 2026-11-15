import Foundation
import VyronAutomation

enum VyronChatAppOpenRequest {
    static func resolve(
        _ prompt: String,
        applications: @autoclosure () -> [DesktopApplication]
    ) -> DesktopApplication? {
        guard let target = targetName(in: prompt) else { return nil }
        let catalog = applications()
        let exactMatches = matchingApplications(in: catalog, names: [target])
        if !exactMatches.isEmpty { return exactMatches.count == 1 ? exactMatches.first : nil }

        var name = target
        while let punctuation = name.last, ".?!".contains(punctuation) {
            name.removeLast()
        }
        name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        if name != target {
            let matches = matchingApplications(in: catalog, names: [name])
            if !matches.isEmpty { return matches.count == 1 ? matches.first : nil }
        }

        let withoutArticle = name.hasPrefix("the ") ? String(name.dropFirst("the ".count)) : name
        var aliases: Set<String> = [withoutArticle]
        for suffix in [" app", " application", ".app"] where name.hasSuffix(suffix) {
            aliases.insert(String(name.dropLast(suffix.count)))
            aliases.insert(String(withoutArticle.dropLast(suffix.count)))
        }
        aliases.remove(name)
        aliases.remove("")
        let matches = matchingApplications(in: catalog, names: aliases)
        return matches.count == 1 ? matches.first : nil
    }

    private static func targetName(in prompt: String) -> String? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.rangeOfCharacter(from: .newlines) == nil else { return nil }
        var command = normalized(trimmed)
        let requestPrefixes = ["please ", "can you ", "can u ", "could you ", "would you ", "i want you to "]
        for prefix in requestPrefixes where command.hasPrefix(prefix) {
            command.removeFirst(prefix.count)
        }
        guard let operation = ["open ", "launch "].first(where: command.hasPrefix) else { return nil }
        return String(command.dropFirst(operation.count))
    }

    private static func matchingApplications(
        in catalog: [DesktopApplication], names: Set<String>
    ) -> [DesktopApplication] {
        guard !names.isEmpty else { return [] }
        return catalog.filter { app in
            names.contains(normalized(app.name))
                || app.bundleIdentifier.map { names.contains($0.lowercased()) } == true
        }
    }

    private static func normalized(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
