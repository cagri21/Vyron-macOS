import Foundation
import XCTest
@testable import Vyron

@MainActor
final class VyronNotificationResourceTests: XCTestCase {
    func testInboxLabelsResolveInEveryBundledLanguage() {
        let labels: [(VyronLanguage, String, String)] = [
            (.english, "Notifications", "Priority"),
            (.turkish, "Bildirimler", "Öncelikli"),
            (.ukrainian, "Сповіщення", "Пріоритетні")
        ]
        for (language, title, priority) in labels {
            XCTAssertEqual(
                VyronResourceBundle.string("notificationTitle", fallback: "Missing", language: language), title
            )
            XCTAssertEqual(
                VyronResourceBundle.string("notificationPriority", fallback: "Missing", language: language), priority
            )
            for key in ["notificationRetry", "notificationOpenBlocked", "notificationStorageError"] {
                XCTAssertNotEqual(VyronResourceBundle.string(key, fallback: "Missing", language: language), "Missing")
            }
        }
    }

    func testUnreadCountUsesBundledPluralRules() {
        let counts: [(VyronLanguage, Int, String)] = [
            (.english, 0, "0 unread notifications"), (.english, 1, "1 unread notification"),
            (.english, 2, "2 unread notifications"), (.turkish, 5, "5 okunmamış bildirim"),
            (.ukrainian, 1, "1 непрочитане сповіщення"), (.ukrainian, 2, "2 непрочитані сповіщення"),
            (.ukrainian, 5, "5 непрочитаних сповіщень"), (.ukrainian, 21, "21 непрочитане сповіщення")
        ]
        for (language, count, expected) in counts {
            XCTAssertEqual(
                VyronResourceBundle.format(
                    "notificationUnreadCount", fallback: "%d unread notifications",
                    arguments: [count], language: language
                ), expected
            )
        }
    }
}
