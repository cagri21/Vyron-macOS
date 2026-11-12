import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronTaskDatePresentationTests: XCTestCase {
    func testTodayAndYesterdayLabelsHonorTheSuppliedLocale() throws {
        let now = try date("2026-11-04T12:00:00Z")
        let today = try date("2026-11-04T09:25:00Z")
        let yesterday = try date("2026-11-03T19:40:00Z")
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let languages: [VyronLanguage] = [.english, .turkish, .ukrainian]
        var todayLabels: Set<String> = []
        for language in languages {
            let locale = Locale(identifier: language.rawValue)
            let todayLabel = VyronTaskDatePresentation.label(
                for: today, relativeTo: now, locale: locale, timeZone: zone
            )
            let yesterdayLabel = VyronTaskDatePresentation.label(
                for: yesterday, relativeTo: now, locale: locale, timeZone: zone
            )
            XCTAssertEqual(todayLabel, VyronResourceBundle.format(
                "trackingTodayAt", fallback: "Today %@",
                arguments: [shortTime(today, locale: locale, zone: zone)], language: language
            ))
            XCTAssertEqual(yesterdayLabel, VyronResourceBundle.format(
                "trackingYesterdayAt", fallback: "Yesterday %@",
                arguments: [shortTime(yesterday, locale: locale, zone: zone)], language: language
            ))
            XCTAssertNotEqual(todayLabel, yesterdayLabel)
            todayLabels.insert(todayLabel)
        }
        XCTAssertEqual(todayLabels.count, 3)
    }

    func testCalendarDayBoundaryUsesSuppliedTimeZone() throws {
        let now = try date("2026-11-04T00:30:00Z")
        let startedAt = try date("2026-11-03T23:50:00Z")
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let istanbul = try XCTUnwrap(TimeZone(identifier: "Europe/Istanbul"))
        let locale = Locale(identifier: "en_US")

        let inUTC = VyronTaskDatePresentation.label(
            for: startedAt, relativeTo: now, locale: locale, timeZone: utc
        )
        let inIstanbul = VyronTaskDatePresentation.label(
            for: startedAt, relativeTo: now, locale: locale, timeZone: istanbul
        )

        XCTAssertEqual(inUTC, VyronResourceBundle.format(
            "trackingYesterdayAt", fallback: "Yesterday %@",
            arguments: [shortTime(startedAt, locale: locale, zone: utc)], language: .english
        ))
        XCTAssertEqual(inIstanbul, VyronResourceBundle.format(
            "trackingTodayAt", fallback: "Today %@",
            arguments: [shortTime(startedAt, locale: locale, zone: istanbul)], language: .english
        ))
        XCTAssertTrue(inUTC.contains(shortTime(startedAt, locale: locale, zone: utc)))
        XCTAssertTrue(inIstanbul.contains(shortTime(startedAt, locale: locale, zone: istanbul)))
    }

    func testOlderTasksShowActualDateAndTimeInsteadOfRelativeDayLabels() throws {
        let now = try date("2026-11-04T12:00:00Z")
        let startedAt = try date("2025-06-14T08:35:00Z")
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let locale = Locale(identifier: "en_US")

        let label = VyronTaskDatePresentation.label(
            for: startedAt, relativeTo: now, locale: locale, timeZone: zone
        )

        XCTAssertTrue(label.contains("2025"))
        XCTAssertTrue(label.contains(shortTime(startedAt, locale: locale, zone: zone)))
        XCTAssertFalse(label.hasPrefix("Today"))
        XCTAssertFalse(label.hasPrefix("Yesterday"))
        XCTAssertFalse(label.contains("tracking"))
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    private func shortTime(_ date: Date, locale: Locale, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
