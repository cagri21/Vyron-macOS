import Foundation
import XCTest
@testable import VyronCore

final class VyronScheduledTaskScheduleTests: XCTestCase {
    private func date(_ text: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: text))
    }

    private func schedule(
        _ startsAt: String,
        recurrence: VyronTaskRecurrence,
        timeZone: String = "America/New_York"
    ) throws -> VyronTaskSchedule {
        VyronTaskSchedule(
            startsAt: try date(startsAt),
            recurrence: recurrence,
            timeZoneIdentifier: timeZone
        )
    }

    func testOnceHasOnlyItsOriginalOccurrence() throws {
        let schedule = try schedule("2026-11-10T10:00:00Z", recurrence: .once)
        XCTAssertEqual(schedule.nextRun(after: try date("2026-11-09T10:00:00Z")), schedule.startsAt)
        XCTAssertNil(schedule.nextRun(after: schedule.startsAt))
        XCTAssertNil(schedule.nextRun(after: try date("2026-11-11T10:00:00Z")))
    }

    func testDailyRetainsSavedTimeZoneAndStartLowerBound() throws {
        let schedule = try schedule("2026-11-10T10:00:00Z", recurrence: .daily, timeZone: "Europe/Istanbul")
        XCTAssertEqual(schedule.nextRun(after: try date("2026-11-01T10:00:00Z")), schedule.startsAt)
        XCTAssertEqual(schedule.nextRun(after: schedule.startsAt), try date("2026-11-11T10:00:00Z"))
        XCTAssertEqual(
            schedule.nextRun(after: try date("2026-12-01T23:00:00Z")),
            try date("2026-12-02T10:00:00Z")
        )
    }

    func testDailyPreservesLocalTimeAcrossSpringClockChange() throws {
        let schedule = try schedule("2026-03-07T14:15:00Z", recurrence: .daily)
        XCTAssertEqual(schedule.nextRun(after: schedule.startsAt), try date("2026-03-08T13:15:00Z"))
    }

    func testMissingLocalTimeMovesForwardPreservingMinutes() throws {
        let schedule = try schedule("2026-03-07T07:30:00Z", recurrence: .daily)
        let transition = try XCTUnwrap(schedule.nextRun(after: schedule.startsAt))
        XCTAssertEqual(transition, try date("2026-03-08T07:30:00Z"))
        XCTAssertEqual(schedule.nextRun(after: transition), try date("2026-03-09T06:30:00Z"))
    }

    func testFallRepeatedHourRunsOnceAtFirstOccurrence() throws {
        let schedule = try schedule("2026-10-31T05:30:00Z", recurrence: .daily)
        let firstOccurrence = try date("2026-11-01T05:30:00Z")
        XCTAssertEqual(schedule.nextRun(after: schedule.startsAt), firstOccurrence)
        XCTAssertEqual(schedule.nextRun(after: firstOccurrence), try date("2026-11-02T06:30:00Z"))
        XCTAssertEqual(
            schedule.nextRun(after: try date("2026-11-01T05:45:00Z")),
            try date("2026-11-02T06:30:00Z")
        )
    }

    func testWeeklyFallRepeatedHourRunsOnceAtFirstOccurrence() throws {
        let schedule = try schedule("2026-10-25T05:30:00Z", recurrence: .weekly)
        XCTAssertEqual(schedule.nextRun(after: schedule.startsAt), try date("2026-11-01T05:30:00Z"))
        XCTAssertEqual(
            schedule.nextRun(after: try date("2026-11-01T05:45:00Z")),
            try date("2026-11-08T06:30:00Z")
        )
    }

    func testWeeklyRetainsWeekdayAndWallTimeAcrossDST() throws {
        let schedule = try schedule("2026-03-01T14:15:00Z", recurrence: .weekly)
        XCTAssertEqual(schedule.nextRun(after: schedule.startsAt), try date("2026-03-08T13:15:00Z"))
        XCTAssertEqual(
            schedule.nextRun(after: try date("2026-03-09T13:15:00Z")),
            try date("2026-03-15T13:15:00Z")
        )
    }

    func testDailyFractionalSecondsDoNotSkipOrRepeatAnOccurrence() throws {
        let start = try date("2026-11-10T10:00:00Z").addingTimeInterval(0.123456)
        let schedule = VyronTaskSchedule(
            startsAt: start,
            recurrence: .daily,
            timeZoneIdentifier: "UTC"
        )
        let next = start.addingTimeInterval(86_400)
        XCTAssertEqual(try XCTUnwrap(schedule.nextRun(after: start)).timeIntervalSince(next), 0, accuracy: 0.000_001)
        XCTAssertEqual(
            try XCTUnwrap(schedule.nextRun(after: next.addingTimeInterval(-0.001))).timeIntervalSince(next),
            0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            try XCTUnwrap(schedule.nextRun(after: next)).timeIntervalSince(next.addingTimeInterval(86_400)),
            0,
            accuracy: 0.000_001
        )
    }

    func testWeeklyFractionalSecondsRetainLocalTimeAcrossDST() throws {
        let start = try date("2026-03-01T14:15:00Z").addingTimeInterval(0.125)
        let schedule = VyronTaskSchedule(
            startsAt: start,
            recurrence: .weekly,
            timeZoneIdentifier: "America/New_York"
        )
        let expected = try date("2026-03-08T13:15:00Z").addingTimeInterval(0.125)
        XCTAssertEqual(
            try XCTUnwrap(schedule.nextRun(after: start)).timeIntervalSince(expected),
            0,
            accuracy: 0.000_001
        )
    }

    func testUnknownZoneAndNonfiniteDatesAreRejected() throws {
        let invalidZone = try schedule("2026-11-10T10:00:00Z", recurrence: .daily, timeZone: "Invalid/Zone")
        XCTAssertThrowsError(try invalidZone.validated())
        XCTAssertNil(invalidZone.nextRun(after: try date("2026-11-01T10:00:00Z")))
        let invalidDate = VyronTaskSchedule(
            startsAt: Date(timeIntervalSinceReferenceDate: .infinity),
            recurrence: .once,
            timeZoneIdentifier: "UTC"
        )
        XCTAssertThrowsError(try invalidDate.validated())
        XCTAssertNil(invalidDate.nextRun(after: Date()))
        let valid = try schedule("2026-11-10T10:00:00Z", recurrence: .daily)
        XCTAssertNil(valid.nextRun(after: Date(timeIntervalSinceReferenceDate: .nan)))
    }
}
