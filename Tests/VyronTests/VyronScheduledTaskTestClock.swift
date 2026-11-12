import Foundation

@MainActor
final class VyronScheduledTaskTestClock {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
}
