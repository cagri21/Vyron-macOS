import Foundation
import XCTest
import VyronLocalization
@testable import Vyron

@MainActor
final class VyronLocalizationTests: XCTestCase {
    func testSystemLanguageResolvesRegionsAndFirstSupportedPreference() {
        XCTAssertEqual(VyronLanguage.system.resolved(preferredLanguages: ["tr-TR"]), .turkish)
        XCTAssertEqual(VyronLanguage.system.resolved(preferredLanguages: ["uk_UA"]), .ukrainian)
        XCTAssertEqual(VyronLanguage.system.resolved(preferredLanguages: ["de-DE", "uk-UA", "tr"]), .ukrainian)
        XCTAssertEqual(VyronLanguage.system.resolved(preferredLanguages: ["en-GB"]), .english)
    }

    func testUnsupportedOrEmptySystemLanguagesUseEnglish() {
        XCTAssertEqual(VyronLanguage.system.resolved(preferredLanguages: ["de-DE", "fr"]), .english)
        XCTAssertEqual(VyronLanguage.system.resolved(preferredLanguages: []), .english)
        XCTAssertEqual(VyronLanguage.turkish.resolved(preferredLanguages: ["uk-UA"]), .turkish)
    }

    func testLanguageSelectionPersistsAndSystemClearsOnlyItsOwnPreference() throws {
        let suite = "VyronLocalizationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("Keep this setting", forKey: "unrelatedPreference")
        let localization = VyronLocalization(defaults: defaults)
        XCTAssertEqual(localization.language, .system)

        localization.language = .turkish
        XCTAssertEqual(defaults.string(forKey: VyronLocalizationDefaultsKey.language.rawValue), "tr")
        XCTAssertEqual(VyronLocalization(defaults: defaults).language, .turkish)
        XCTAssertEqual(localization.locale.identifier, "tr")

        localization.language = .ukrainian
        XCTAssertEqual(VyronLocalization(defaults: defaults).language, .ukrainian)
        XCTAssertEqual(localization.locale.identifier, "uk")

        localization.language = .system
        XCTAssertNil(defaults.object(forKey: VyronLocalizationDefaultsKey.language.rawValue))
        XCTAssertEqual(VyronLocalization(defaults: defaults).language, .system)
        XCTAssertEqual(defaults.string(forKey: "unrelatedPreference"), "Keep this setting")
    }

    func testInvalidSavedSelectionFollowsSystem() throws {
        let suite = "VyronLocalizationTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: VyronLocalizationDefaultsKey.language.rawValue)
        XCTAssertEqual(VyronLocalization(defaults: defaults).language, .system)
    }

    func testBundledLanguagesResolveTranslatedText() {
        XCTAssertEqual(VyronResourceBundle.string("languageTitle", fallback: "Language", language: .english), "Language")
        XCTAssertEqual(VyronResourceBundle.string("languageTitle", fallback: "Language", language: .turkish), "Dil")
        XCTAssertEqual(
            VyronResourceBundle.string("languageTitle", fallback: "Language", language: .ukrainian),
            "Мова"
        )
        let system = VyronResourceBundle.localized(for: .system, preferredLanguages: ["de", "uk_UA"])
        XCTAssertEqual(system.localizedString(forKey: "languageTitle", value: nil, table: nil), "Мова")
    }

    func testMissingKeyDisplaysEnglishFallbackInsteadOfRawKey() {
        XCTAssertEqual(
            VyronResourceBundle.string(
                "missingLocalizationFixture", fallback: "English fallback", language: .ukrainian
            ),
            "English fallback"
        )
    }

    func testPluralCountsUseLanguageGrammar() {
        let examples: [(VyronLanguage, Int, String)] = [
            (.english, 1, "1 file"), (.english, 2, "2 files"),
            (.turkish, 1, "1 dosya"), (.turkish, 5, "5 dosya"),
            (.ukrainian, 1, "1 файл"), (.ukrainian, 2, "2 файли"),
            (.ukrainian, 5, "5 файлів"), (.ukrainian, 11, "11 файлів"),
            (.ukrainian, 21, "21 файл"), (.ukrainian, 22, "22 файли")
        ]
        for (language, count, expected) in examples {
            XCTAssertEqual(
                VyronResourceBundle.format(
                    "appInspectorFilesCount", fallback: "%d files", arguments: [count], language: language
                ),
                expected
            )
        }
    }

    func testInterpolationPreservesDynamicContentAndLineBreaks() {
        let command = "echo 100%"
        let reason = "A user-provided reason with %@ in it"
        let path = "/Projects/Мій проєкт"
        XCTAssertEqual(
            VyronResourceBundle.format(
                "generalCommandReviewDetails",
                fallback: "%@\n\n%@\n\nProject: %@",
                arguments: [command, reason, path],
                language: .ukrainian
            ),
            "\(command)\n\n\(reason)\n\nПроєкт: \(path)"
        )
        XCTAssertEqual(
            VyronResourceBundle.string(
                "appAutomationAgentExample", fallback: "Example", language: .english
            ),
            "For example, open Calculator and work out 18% of 2450"
        )
    }
}
