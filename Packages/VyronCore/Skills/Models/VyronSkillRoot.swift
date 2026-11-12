import Foundation

public struct VyronSkillRoot: Sendable, Equatable {
    public let directoryURL: URL
    public let source: VyronSkillSource
    public let scope: VyronSkillScope

    public init(directoryURL: URL, source: VyronSkillSource, scope: VyronSkillScope) {
        self.directoryURL = directoryURL.standardizedFileURL
        self.source = source
        self.scope = scope
    }

    public static func local(homeDirectory: URL, projectDirectory: URL? = nil) -> [Self] {
        var roots = [
            Self(
                directoryURL: homeDirectory.appendingPathComponent("Library/Application Support/VyronAI/Skills"),
                source: .agents,
                scope: .personal
            ),
            Self(
                directoryURL: homeDirectory.appendingPathComponent(".codex/skills"),
                source: .codex,
                scope: .personal
            ),
            Self(
                directoryURL: homeDirectory.appendingPathComponent(".claude/skills"),
                source: .claude,
                scope: .personal
            ),
            Self(
                directoryURL: homeDirectory.appendingPathComponent(".agents/skills"),
                source: .agents,
                scope: .personal
            ),
            Self(
                directoryURL: homeDirectory.appendingPathComponent(".codex/plugins/cache"),
                source: .codex,
                scope: .plugin
            ),
            Self(
                directoryURL: homeDirectory.appendingPathComponent(".claude/plugins/cache"),
                source: .claude,
                scope: .plugin
            )
        ]
        if let projectDirectory {
            roots += [
                Self(
                    directoryURL: projectDirectory.appendingPathComponent(".codex/skills"),
                    source: .codex,
                    scope: .project
                ),
                Self(
                    directoryURL: projectDirectory.appendingPathComponent(".claude/skills"),
                    source: .claude,
                    scope: .project
                ),
                Self(
                    directoryURL: projectDirectory.appendingPathComponent(".agents/skills"),
                    source: .agents,
                    scope: .project
                )
            ]
        }
        return roots
    }
}
