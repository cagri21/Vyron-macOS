import Foundation

struct VyronSkillInvocationParser {
    func names(in prompt: String) -> [String] {
        var names: [String] = []
        var fence: String?
        for line in prompt.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix { $0 == trimmed.first })
                if let active = fence, active.first == marker.first, marker.count >= active.count {
                    fence = nil
                } else if fence == nil {
                    fence = marker
                }
                continue
            }
            guard fence == nil else { continue }
            let text = withoutInlineCode(trimmed)
            if text.hasPrefix("/") {
                let token = String(text.dropFirst().prefix { !$0.isWhitespace })
                if isCommand(token) { names.append(token) }
            }
            let characters = Array(text)
            for index in characters.indices where characters[index] == "$" {
                if index > 0, !characters[index - 1].isWhitespace,
                    characters[index - 1] != "[", characters[index - 1] != "(" { continue }
                let name = String(characters[(index + 1)...].prefix { isCommandCharacter($0) })
                guard !name.isEmpty else { continue }
                let end = index + 1 + name.count
                if end < characters.count, characters[end] == "/" { continue }
                names.append(name)
            }
        }
        return names
    }

    private func withoutInlineCode(_ line: String) -> String {
        var delimiterLength: Int?
        var result = ""
        let characters = Array(line)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "`" {
                let length = characters[index...].prefix { $0 == "`" }.count
                if delimiterLength == length { delimiterLength = nil } else if delimiterLength == nil {
                    delimiterLength = length
                }
                result.append(String(repeating: " ", count: length))
                index += length
            } else {
                result.append(delimiterLength == nil ? character : " ")
                index += 1
            }
        }
        return result
    }

    private func isCommand(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy(isCommandCharacter)
    }

    private func isCommandCharacter(_ value: Character) -> Bool {
        value.isASCII && (value.isLetter || value.isNumber || "-_.:".contains(value))
    }
}
