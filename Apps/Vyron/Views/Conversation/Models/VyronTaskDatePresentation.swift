import Foundation

enum VyronTaskDatePresentation {
    static func eventTime(for date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    static func label(for date: Date, relativeTo now: Date, locale: Locale, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let time = formatter.string(from: date)
        let language = VyronLanguage.system.resolved(preferredLanguages: [locale.identifier])
        // This date boundary must honor its explicit locale, independent of global app preferences.
        if calendar.isDate(date, inSameDayAs: now) {
            return VyronResourceBundle.format(
                "trackingTodayAt", fallback: "Today %@", arguments: [time], language: language
            )
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday) {
            return VyronResourceBundle.format(
                "trackingYesterdayAt", fallback: "Yesterday %@", arguments: [time], language: language
            )
        }
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}
