import XCTest
@testable import Vyron

@MainActor
final class VyronTrackingLocalizationTests: XCTestCase {
    func testHelperCountsUseLanguagePluralRules() {
        let cases: [(VyronLanguage, Int, String)] = [
            (.english, 1, "1 helper started working"),
            (.english, 3, "3 helpers started working"),
            (.turkish, 2, "2 yardımcı çalışmaya başladı"),
            (.ukrainian, 1, "1 помічник почав роботу"),
            (.ukrainian, 3, "3 помічники почали роботу")
        ]
        for (language, count, expected) in cases {
            XCTAssertEqual(
                VyronResourceBundle.format(
                    "trackingHelpersStarted", fallback: "%d helpers started working",
                    arguments: [count], language: language
                ),
                expected
            )
        }
    }

    func testHelperNameRemainsDynamicTextInsideTranslatedLabel() {
        let name = "Review %@ Sources/Інтерфейс.swift"
        XCTAssertEqual(
            VyronResourceBundle.format(
                "trackingHelperStarted", fallback: "%@ started working",
                arguments: [name], language: .turkish
            ),
            "\(name) çalışmaya başladı"
        )
    }
}
