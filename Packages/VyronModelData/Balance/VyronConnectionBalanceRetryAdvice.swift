import Foundation

enum VyronConnectionBalanceRetryAdvice {
    static func deadline(from header: String?, now: Date) -> Date? {
        guard let header else { return nil }
        let text = header.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if text.utf8.allSatisfy({ (48...57).contains($0) }) {
            guard let seconds = TimeInterval(text), seconds.isFinite, seconds >= 0 else { return nil }
            let deadline = now.timeIntervalSinceReferenceDate + seconds
            return deadline.isFinite ? Date(timeIntervalSinceReferenceDate: deadline) : nil
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        formatter.isLenient = false
        guard let date = formatter.date(from: text), formatter.string(from: date) == text,
            date.timeIntervalSinceReferenceDate.isFinite
        else { return nil }
        return date
    }
}
