import XCTest
@testable import Vyron

final class VyronCodeInspectionIntentTests: XCTestCase {
    func testCompleteEnglishInspectionRequestsMatchAcrossTheSupportedVerbsAndObjects() {
        for verb in ["analyze", "analyse", "review", "inspect"] {
            for article in ["", "the ", "this "] {
                for object in ["code", "codebase", "project", "repo", "repository"] {
                    let prompt = "\(verb) \(article)\(object)"
                    XCTAssertTrue(VyronCodeInspectionIntent.matches(prompt), prompt)
                }
            }
        }
    }

    func testPolitenessWhitespaceAndReadOnlyImprovementRequestsMatch() {
        for prompt in [
            "please analyze the code", "Can you review this project?", "Could you please inspect the repository?",
            "Please can you analyse the codebase.", "would you review the repo", "ANALYZE THE CODE!",
            " \n analyze\t the   code \n", "analyze the code and find improvements",
            "please review this codebase and suggest improvements."
        ] {
            XCTAssertTrue(VyronCodeInspectionIntent.matches(prompt), prompt)
        }
    }

    func testCommonTurkishAndUkrainianStandaloneInspectionRequestsMatch() {
        for prompt in [
            "kodu analiz et", "bu kodu incele", "projeyi gözden geçir", "depoyu incele",
            "Lütfen bu projeyi analiz et.", "KOD TABANINI İNCELE", "kodu incele ve iyileştirmeler öner",
            "lütfen kodu analiz et ve iyileştirmeleri bul", "kodu gözden geçir ve iyileştirme önerileri sun",
            "проаналізуй код", "Переглянь цей проєкт.", "дослідіть репозиторій", "проаналізуйте кодову базу",
            "будь ласка, переглянь код", "проаналізуй код і запропонуй покращення",
            "переглянь проєкт та знайди поліпшення"
        ] {
            XCTAssertTrue(VyronCodeInspectionIntent.matches(prompt), prompt)
        }
    }

    func testMixedEditingExecutionAndExternalActionsRemainUnclassified() {
        for prompt in [
            "analyze the code and fix the bug", "review the project then implement the plan",
            "inspect the code and run tests", "analyze the code and suggest improvements, then implement them",
            "analyze the code and find improvements and apply them", "review the repo; delete unused files",
            "analyze the code && execute the script", "review the code and publish the results",
            "inspect the repository at https://example.com/repo", "fix the code", "implement that plan",
            "kodu analiz et ve düzelt", "projeyi incele ve testleri çalıştır",
            "проаналізуй код і виправ помилки", "переглянь проєкт та запусти тести"
        ] {
            XCTAssertFalse(VyronCodeInspectionIntent.matches(prompt), prompt)
        }
    }

    func testQuotedCodeDependentQuestionsAndLongerContextDoNotMatchByKeywordsAlone() {
        for prompt in [
            "", " ", "code", "review that", "continue", "yes", "Should I analyze the code?",
            "How can I review this project?", "Which code should I inspect?", "analyze the code above",
            "review my project", "analyze the code: def run(): pass", "analyze the code\nlet value = 1",
            "`analyze the code`", "\"analyze the code\"", "```text\nanalyze the code\n```",
            "The instruction says analyze the code.", "please analyze the code without changing the files",
            "bu kod nasıl analiz edilir?", "поясни, як переглянути код"
        ] {
            XCTAssertFalse(VyronCodeInspectionIntent.matches(prompt), prompt)
        }
    }
}
