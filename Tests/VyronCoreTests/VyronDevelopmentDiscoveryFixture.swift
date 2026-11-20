import Foundation
import XCTest
import VyronDevelopment

struct VyronDevelopmentDiscoveryFixture: Sendable {
    static let sourcePath = "examples/demo/infer.py"
    static let sourceText = "def normalize_identifier(value):\n    return value.strip().lower()\n"

    let root: URL
    let workspace: DevelopmentWorkspace
    let contents: [String: Data]

    init(documentCount: Int = 140) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronDiscovery-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var contents: [String: Data] = [
            "README.md": Data("Documentation and local Python utilities. A mention of ghost.py is not a file.\n".utf8),
            Self.sourcePath: Data(Self.sourceText.utf8),
            "Sources/Utility.swift": Data("let documentationOnly = false\n".utf8),
            ".env": Data("synthetic excluded fixture, not a credential\n".utf8)
        ]
        for index in 0..<documentCount {
            let name = String(format: "%03d", index) + "-reference-"
                + String(repeating: "long-context-", count: 5) + "İnceleme-検証-\"quoted\".md"
            contents["docs/reference/" + name] = Data("Documentation mentioning ghost.py and Python.\n".utf8)
        }
        do {
            for (path, data) in contents {
                let file = root.appendingPathComponent(path)
                try FileManager.default.createDirectory(
                    at: file.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                try data.write(to: file)
            }
            workspace = try DevelopmentWorkspace(rootURL: root)
        } catch {
            try FileManager.default.removeItem(at: root)
            throw error
        }
        self.root = root
        self.contents = contents
    }

    var visiblePaths: Set<String> { Set(contents.keys.filter { !$0.hasPrefix(".") }) }

    func assertUnchanged(file: StaticString = #filePath, line: UInt = #line) throws {
        let enumerator = try XCTUnwrap(
            FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]),
            file: file,
            line: line
        )
        var actual: Set<String> = []
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            actual.insert(String(url.path.dropFirst(root.path.count + 1)))
        }
        XCTAssertEqual(actual, Set(contents.keys), file: file, line: line)
        for (path, data) in contents {
            XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(path)), data, file: file, line: line)
        }
    }

    func remove() throws { try FileManager.default.removeItem(at: root) }
}
