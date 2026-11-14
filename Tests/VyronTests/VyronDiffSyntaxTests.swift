import SwiftUI
import XCTest
@testable import Vyron

@MainActor
final class VyronDiffSyntaxTests: XCTestCase {
    func testSwiftColorsCommonTokensAndPreservesSource() {
        let source = "    let café: Bool = true // review me"
        let highlighted = VyronDiffSyntax.highlight(source, filename: "Sources/Example.swift")

        XCTAssertEqual(String(highlighted.characters), source)
        XCTAssertEqual(color(for: "let", in: highlighted), Palette.diffSyntaxKeyword)
        XCTAssertEqual(color(for: "café", in: highlighted), Palette.diffSyntaxName)
        XCTAssertEqual(color(for: "Bool", in: highlighted), Palette.diffSyntaxType)
        XCTAssertEqual(color(for: "true", in: highlighted), Palette.diffSyntaxLiteral)
        XCTAssertEqual(color(for: "// review me", in: highlighted), Palette.diffSyntaxComment)
    }

    func testStringMarkersAndLanguageSpecificCommentsKeepTheirRoles() {
        let source = "print(\"https://example.test#heading\") # follow-up"
        let highlighted = VyronDiffSyntax.highlight(source, filename: "sample.py")

        XCTAssertEqual(String(highlighted.characters), source)
        XCTAssertEqual(color(for: "\"https://example.test#heading\"", in: highlighted), Palette.diffSyntaxLiteral)
        XCTAssertEqual(color(for: "# follow-up", in: highlighted), Palette.diffSyntaxComment)
    }

    func testUnknownFormatsAndLargeLinesKeepPlainSource() {
        let short = "let value = true"
        let long = "let value = \"" + String(repeating: "x", count: 5_000) + "\""
        XCTAssertEqual(VyronDiffSyntax.highlight(short, filename: "README.md"), AttributedString(short))
        XCTAssertEqual(VyronDiffSyntax.highlight(long, filename: "source.swift"), AttributedString(long))
    }

    private func color(for token: String, in source: AttributedString) -> Color? {
        source.runs.first { String(source[$0.range].characters) == token }?.foregroundColor
    }
}
