import Foundation

struct VyronSkillMetadataParser {
    func parse(_ content: String, fallbackName: String) -> VyronSkillMetadata? {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        let lines = normalized.components(separatedBy: "\n")
        guard lines.first == "---" else {
            return metadata(name: fallbackName, description: bodyDescription(lines))
        }
        guard let closing = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }) else {
            return nil
        }
        var name = fallbackName
        var description = ""
        var index = 1
        while index < closing {
            let line = lines[index]
            index += 1
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), let colon = line.firstIndex(of: ":") else {
                continue
            }
            let key = String(line[..<colon])
            guard key == "name" || key == "description" else { continue }
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            let parsed: String
            if [">", ">-", ">+", "|", "|-", "|+"].contains(value) {
                var block: [String] = []
                while index < closing, lines[index].hasPrefix(" ") || lines[index].isEmpty {
                    block.append(lines[index].trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                parsed = block.joined(separator: value.hasPrefix(">") ? " " : "\n")
            } else {
                if value.hasPrefix("\"") || value.hasPrefix("'") {
                    while quotedEnd(in: value) == nil, index < closing {
                        guard lines[index].isEmpty || lines[index].hasPrefix(" ") else { return nil }
                        let continuation = lines[index].trimmingCharacters(in: .whitespaces)
                        value += continuation.isEmpty ? "\n" : " " + continuation
                        index += 1
                    }
                } else {
                    while index < closing, lines[index].hasPrefix(" ") {
                        value += " " + lines[index].trimmingCharacters(in: .whitespaces)
                        index += 1
                    }
                }
                guard let scalar = scalar(value) else { return nil }
                parsed = scalar
            }
            if key == "name" {
                name = parsed
            } else {
                description = parsed
            }
        }
        if description.isEmpty {
            description = bodyDescription(Array(lines.dropFirst(closing + 1)))
        }
        return metadata(name: name, description: description)
    }

    private func scalar(_ value: String) -> String? {
        if value.hasPrefix("\"") || value.hasPrefix("'") {
            guard let end = quotedEnd(in: value) else { return nil }
            let trailing = value[value.index(after: end)...].trimmingCharacters(in: .whitespaces)
            guard trailing.isEmpty || trailing.hasPrefix("#") else { return nil }
            let quoted = String(value[...end])
            if value.hasPrefix("'") {
                return String(quoted.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
            }
            let json = quoted.replacingOccurrences(of: "\n", with: "\\n")
            guard let bytes = json.data(using: .utf8) else { return nil }
            do {
                return try JSONDecoder().decode(String.self, from: bytes)
            } catch {
                // A malformed quoted scalar invalidates the document's metadata.
                return nil
            }
        }
        guard !["[", "{", "&", "*"].contains(where: value.hasPrefix) else { return nil }
        return value.components(separatedBy: " #").first ?? ""
    }

    private func quotedEnd(in value: String) -> String.Index? {
        guard let quote = value.first else { return nil }
        var cursor = value.index(after: value.startIndex)
        while cursor < value.endIndex {
            let next = value.index(after: cursor)
            if value[cursor] == "\\", quote == "\"", next < value.endIndex {
                cursor = value.index(after: next)
                continue
            }
            if value[cursor] == quote {
                if quote == "'", next < value.endIndex, value[next] == "'" {
                    cursor = value.index(after: next)
                    continue
                }
                return cursor
            }
            cursor = next
        }
        return nil
    }

    private func metadata(name: String, description: String) -> VyronSkillMetadata? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("\n"), !name.contains("\0") else { return nil }
        return VyronSkillMetadata(
            name: String(name.prefix(160)),
            description: String(description.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2_048))
        )
    }

    private func bodyDescription(_ lines: [String]) -> String {
        lines.first(where: { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return !trimmed.isEmpty && !trimmed.hasPrefix("#") && !trimmed.hasPrefix("```")
        })?.trimmingCharacters(in: .whitespaces) ?? ""
    }
}
