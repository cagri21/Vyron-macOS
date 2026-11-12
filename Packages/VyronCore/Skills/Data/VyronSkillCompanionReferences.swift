import Foundation

/// Resolves only a document's exact local Markdown destinations into the already discovered skill catalog.
struct VyronSkillCompanionReferences {
    func resolve(
        path: String,
        from command: VyronSkillCommand,
        catalog: [VyronSkillCommand]
    ) throws -> VyronSkillResourceReference? {
        guard path.utf8.count <= 2_048, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
            URLComponents(string: path)?.scheme == nil
        else { return nil }
        let directory = command.skill.fileURL.deletingLastPathComponent()
        let document = try VyronSkillResourceReader().read(relativePath: "SKILL.md", directory: directory)
        guard try destinations(in: document).contains(path) else { return nil }
        let withoutFragment = String(path.prefix { $0 != "#" })
        guard let decoded = withoutFragment.removingPercentEncoding, !decoded.isEmpty,
            !decoded.hasPrefix("/"), !decoded.contains("?"), !decoded.contains("\\"), !decoded.contains("\0"),
            URLComponents(string: decoded)?.scheme == nil
        else { return nil }
        guard let targetComponents = lexicalComponents(for: decoded, directory: directory) else { return nil }
        // The narrowest known owner wins if a library contains nested skill documents.
        for candidate in catalog.sorted(by: {
            $0.skill.fileURL.pathComponents.count > $1.skill.fileURL.pathComponents.count
        }) {
            let owner = candidate.skill.fileURL.deletingLastPathComponent()
            guard targetComponents.starts(with: owner.pathComponents) else { continue }
            let relative = targetComponents.dropFirst(owner.pathComponents.count).joined(separator: "/")
            guard !relative.isEmpty else { continue }
            return VyronSkillResourceReference(command: candidate, relativePath: relative)
        }
        return nil
    }

    private func lexicalComponents(for path: String, directory: URL) -> [String]? {
        // Foundation's file standardization may resolve links while removing '..'. Keep the original path
        // components so the reader can reject every symbolic link with openat/O_NOFOLLOW instead.
        var components = directory.pathComponents
        for component in path.split(separator: "/", omittingEmptySubsequences: false) {
            switch component {
            case ".", "": continue
            case "..":
                guard components.count > 1 else { return nil }
                components.removeLast()
            default: components.append(String(component))
            }
        }
        return components
    }

    private func destinations(in document: String) throws -> Set<String> {
        // Only inline Markdown links are references. Reference-style, remote, and bare paths grant no access.
        let expression = try NSRegularExpression(pattern: #"!?\[[^\]\n]*\]\(\s*(?:<([^>\n]+)>|([^\s()]+))(?:\s+["'][^\n]*["'])?\s*\)"#)
        let range = NSRange(document.startIndex..<document.endIndex, in: document)
        return Set(expression.matches(in: document, range: range).compactMap { match in
            let destination = match.range(at: 1).location == NSNotFound ? match.range(at: 2) : match.range(at: 1)
            guard let range = Range(destination, in: document) else { return nil }
            return String(document[range])
        })
    }
}
