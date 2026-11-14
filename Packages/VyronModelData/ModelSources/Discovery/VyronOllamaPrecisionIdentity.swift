import Foundation

struct VyronOllamaPrecisionIdentity: Equatable {
    let family: String
    let variant: String

    var libraryURL: URL? {
        guard !family.contains("/") else { return nil }
        return URL(string: "https://ollama.com/library/\(family)")
    }
}
