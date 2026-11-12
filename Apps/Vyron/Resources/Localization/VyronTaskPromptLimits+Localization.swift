import Foundation
import VyronModelDomain

extension VyronTaskPromptLimits {
    static var localizedMaximumCharacters: String {
        maximumCharacters.formatted(.number.locale(VyronResourceBundle.locale))
    }

    static var localizedMaximumKilobytes: String {
        Measurement(value: Double(maximumUTF8Bytes), unit: UnitInformationStorage.bytes)
            .converted(to: .kilobytes).value.formatted(.number.locale(VyronResourceBundle.locale))
    }
}
