import Foundation

public struct VyronTaskSchedule: Codable, Equatable, Sendable {
    public var startsAt: Date
    public var recurrence: VyronTaskRecurrence
    public var timeZoneIdentifier: String

    public init(startsAt: Date, recurrence: VyronTaskRecurrence, timeZoneIdentifier: String) {
        self.startsAt = startsAt
        self.recurrence = recurrence
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public func validated() throws -> Self {
        guard startsAt.timeIntervalSinceReferenceDate.isFinite,
            TimeZone(identifier: timeZoneIdentifier) != nil
        else { throw VyronScheduledTaskError.invalidSchedule }
        return self
    }

    /// Returns a single future occurrence, retaining the original local time across daylight saving changes.
    public func nextRun(after date: Date) -> Date? {
        guard date.timeIntervalSinceReferenceDate.isFinite,
            startsAt.timeIntervalSinceReferenceDate.isFinite,
            let timeZone = TimeZone(identifier: timeZoneIdentifier)
        else { return nil }
        if startsAt > date { return startsAt }
        guard recurrence != .once else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.hour, .minute, .second], from: startsAt)
        if recurrence == .weekly {
            components.weekday = calendar.component(.weekday, from: startsAt)
        }
        // Match calendar units independently of floating-point nanosecond reconstruction.
        let interval = startsAt.timeIntervalSinceReferenceDate
        let fractionalSecond = interval - floor(interval)
        guard let day = calendar.dateInterval(of: .day, for: date) else { return nil }
        // Starting inside a repeated hour can select its second occurrence even with `.first`.
        // Resolve the day's canonical occurrence before deciding whether it has been consumed.
        guard let next = calendar.nextDate(
            after: day.start.addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first
        ) else { return nil }
        let occurrence = next.addingTimeInterval(fractionalSecond)
        if occurrence > date { return occurrence }
        return calendar.nextDate(
            after: day.end.addingTimeInterval(-1),
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents,
            repeatedTimePolicy: .first
        )?.addingTimeInterval(fractionalSecond)
    }
}
