import Foundation

enum VyronDiffSyntaxLanguage {
    case swift
    case javaScript
    case python
    case cFamily

    init?(filename: String) {
        switch (filename as NSString).pathExtension.lowercased() {
        case "swift": self = .swift
        case "js", "jsx", "mjs", "cjs", "ts", "tsx": self = .javaScript
        case "py", "pyi": self = .python
        case "c", "h", "cc", "cpp", "cxx", "hpp", "m", "mm", "java": self = .cFamily
        default: return nil
        }
    }

    var keywords: Set<String> {
        switch self {
        case .swift: Self.swiftKeywords
        case .javaScript: Self.javaScriptKeywords
        case .python: Self.pythonKeywords
        case .cFamily: Self.cFamilyKeywords
        }
    }

    private static let swiftKeywords: Set<String> = [
        "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
        "convenience", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "fileprivate",
        "final", "for", "func", "get", "guard", "if", "import", "in", "init", "inout", "internal", "is", "lazy",
        "let", "mutating", "nonisolated", "open", "override", "package", "private", "protocol", "public",
        "repeat", "required", "return", "set", "some", "static", "struct", "subscript", "super", "switch", "throw",
        "throws", "try", "typealias", "var", "where", "while"
    ]
    private static let javaScriptKeywords: Set<String> = [
        "abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "debugger",
        "declare", "default", "delete", "do", "else", "enum", "export", "extends", "finally", "for", "from",
        "function", "if", "implements", "import", "in", "instanceof", "interface", "keyof", "let", "new",
        "of", "private", "protected", "public", "readonly", "return", "satisfies", "static", "super", "switch",
        "throw", "try", "type", "typeof", "var", "void", "while", "with", "yield"
    ]
    private static let pythonKeywords: Set<String> = [
        "and", "as", "assert", "async", "await", "break", "case", "class", "continue", "def", "del", "elif",
        "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "match",
        "nonlocal", "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"
    ]
    private static let cFamilyKeywords: Set<String> = [
        "abstract", "auto", "bool", "break", "case", "catch", "char", "class", "const", "constexpr", "continue",
        "default", "delete", "do", "double", "else", "enum", "explicit", "extern", "false", "final", "finally",
        "float", "for", "goto", "if", "implements", "import", "inline", "int", "interface", "long", "namespace",
        "new", "package", "private", "protected", "public", "return", "short", "signed", "sizeof", "static",
        "struct", "super", "switch", "template", "this", "throw", "throws", "try", "typedef", "union",
        "unsigned", "using", "virtual", "void", "volatile", "while"
    ]
}
