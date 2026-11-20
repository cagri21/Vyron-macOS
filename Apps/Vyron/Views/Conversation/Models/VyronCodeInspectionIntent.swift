import Foundation

/// Recognizes complete, standalone inspection requests without reclassifying mixed or dependent work.
enum VyronCodeInspectionIntent {
    static func matches(_ prompt: String) -> Bool {
        let text = prompt.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.range(of: englishPattern, options: [.regularExpression, .caseInsensitive]) != nil
            || text.lowercased(with: Locale(identifier: "tr_TR"))
                .range(of: turkishPattern, options: .regularExpression) != nil
            || text.range(of: ukrainianPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let englishPattern =
        #"\A(?:(?:please )?(?:can|could|would) you (?:please )?|please )?"#
        + #"(?:analyze|analyse|review|inspect) (?:(?:the|this) )?(?:code|codebase|project|repo|repository)"#
        + #"(?: and (?:find|suggest) improvements)?[.!?]?\z"#

    private static let turkishPattern =
        #"\A(?:lütfen )?(?:bu )?(?:kodu|kod tabanını|projeyi|depoyu) (?:analiz et|incele|gözden geçir)"#
        + #"(?: ve (?:iyileştirmeleri bul|iyileştirmeler öner|iyileştirme önerileri sun))?[.!?]?\z"#

    private static let ukrainianPattern =
        #"\A(?:будь ласка,? )?(?:проаналізуй|проаналізуйте|переглянь|перегляньте|досліди|дослідіть) "#
        + #"(?:(?:цей|цю) )?(?:код|кодову базу|проєкт|проект|репозиторій)"#
        + #"(?: (?:і|та) (?:запропонуй|запропонуйте|знайди|знайдіть) (?:покращення|поліпшення))?[.!?]?\z"#
}
