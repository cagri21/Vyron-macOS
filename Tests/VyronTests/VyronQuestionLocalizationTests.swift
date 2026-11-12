import XCTest
@testable import Vyron

@MainActor
final class VyronQuestionLocalizationTests: XCTestCase {
    func testQuestionControlsHaveTranslationsForEverySupportedLanguage() {
        let examples: [(VyronLanguage, [String])] = [
            (.english, [
                "Waiting for your answer", "Write your own answer…", "Continue",
                "Please shorten your answer to continue.", "Your answer was received"
            ]),
            (.turkish, [
                "Yanıtınız bekleniyor", "Kendi yanıtınızı yazın…", "Devam et",
                "Devam etmek için yanıtınızı kısaltın.", "Yanıtınız alındı"
            ]),
            (.ukrainian, [
                "Очікуємо на вашу відповідь", "Напишіть власну відповідь…", "Продовжити",
                "Скоротіть відповідь, щоб продовжити.", "Вашу відповідь отримано"
            ])
        ]
        let keys = [
            "questionWaitingForAnswer", "questionAnswerPlaceholder", "questionContinueTask",
            "questionAnswerTooLong", "questionAnswerReceived"
        ]
        for (language, expected) in examples {
            for (key, value) in zip(keys, expected) {
                XCTAssertEqual(
                    VyronResourceBundle.string(key, fallback: "Missing question translation", language: language),
                    value
                )
            }
        }
    }

    func testCompactQuestionCardActionsAndSkipInstructionAreLocalized() {
        let examples: [(VyronLanguage, [String])] = [
            (.english, [
                "Question", "Send", "Skip", "Skip this question and use your best judgment.",
                "Dismiss question and stop task"
            ]),
            (.turkish, [
                "Soru", "Gönder", "Atla", "Bu soruyu atla ve en uygun kararı kendin ver.",
                "Soruyu kapat ve görevi durdur"
            ]),
            (.ukrainian, [
                "Запитання", "Надіслати", "Пропустити", "Пропусти це запитання й ухвали рішення на власний розсуд.",
                "Закрити запитання й зупинити завдання"
            ])
        ]
        let keys = [
            "questionTitle", "questionSend", "questionSkip", "questionSkippedAnswer", "questionDismiss"
        ]
        for (language, expected) in examples {
            XCTAssertEqual(expected.count, keys.count)
            for (key, value) in zip(keys, expected) {
                XCTAssertEqual(
                    VyronResourceBundle.string(key, fallback: "Missing question translation", language: language),
                    value
                )
            }
        }
    }
}
