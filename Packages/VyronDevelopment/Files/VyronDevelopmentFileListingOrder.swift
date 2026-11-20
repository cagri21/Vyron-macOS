import Foundation

enum VyronDevelopmentFileListingOrder {
    private static let rootManifests: Set<String> = [
        "agents.md", "agents.override.md", "package.swift", "package.json", "pyproject.toml", "requirements.txt",
        "cargo.toml", "go.mod", "build.gradle", "build.gradle.kts", "pubspec.yaml", "makefile", "cmakelists.txt"
    ]
    private static let sourceExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "rs", "py", "js", "jsx", "ts", "tsx",
        "kt", "kts", "java", "go", "rb", "sql", "graphql", "proto", "sh", "bash", "zsh", "vue", "svelte",
        "dart", "r", "lua", "cs", "fs", "fsx", "ex", "exs", "erl", "hrl", "clj", "cljs", "pl", "php",
        "jl", "scala", "groovy", "html", "css", "scss", "sass", "less"
    ]

    static func precedes(_ first: DevelopmentFile, _ second: DevelopmentFile) -> Bool {
        let firstRank = rank(first.path)
        let secondRank = rank(second.path)
        if firstRank != secondRank { return firstRank < secondRank }
        return first.path < second.path
    }

    private static func rank(_ path: String) -> Int {
        let lower = path.lowercased()
        if !path.contains("/"), rootManifests.contains(lower) || lower.hasPrefix("readme") { return 0 }
        return sourceExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) ? 1 : 2
    }
}
