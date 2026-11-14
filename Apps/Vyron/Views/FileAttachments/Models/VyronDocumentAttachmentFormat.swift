import Foundation
import UniformTypeIdentifiers

enum VyronDocumentAttachmentFormat {
    private static let extensions: Set<String> = [
        "txt", "text", "md", "markdown", "rst", "adoc",
        "csv", "tsv", "json", "jsonl", "xml", "yaml", "yml", "toml", "ini",
        "swift", "c", "h", "cpp", "hpp", "m", "mm", "rs", "go", "java", "kt", "kts",
        "js", "jsx", "mjs", "ts", "tsx", "html", "htm", "css",
        "py", "rb", "php", "sql", "sh", "zsh", "bash"
    ]
    private static let extensionlessNames: Set<String> = ["dockerfile", "license", "makefile", "readme"]

    private static let baseTypes: [UTType] = [
        .plainText, .sourceCode, .commaSeparatedText, .tabSeparatedText, .json, .xml, .yaml, .html
    ]
    static let contentTypes: [UTType] = baseTypes + extensions.sorted().compactMap { suffix in
        guard let type = UTType(filenameExtension: suffix), !type.conforms(to: .audiovisualContent),
            !type.conforms(to: .image), !type.conforms(to: .archive), !baseTypes.contains(type)
        else { return nil }
        return type
    }

    static func supports(filename: String) -> Bool {
        guard !filename.contains("/"), VyronFolderAttachmentPolicy.allows(filename) else { return false }
        let fileExtension = (filename as NSString).pathExtension.lowercased()
        if fileExtension.isEmpty { return extensionlessNames.contains(filename.lowercased()) }
        if extensions.contains(fileExtension) { return true }
        return UTType(filenameExtension: fileExtension)?.conforms(to: .plainText) == true
    }

    static func prefersType(_ type: UTType) -> Bool {
        type != .text && contentTypes.contains { type.conforms(to: $0) }
    }
}
