import Foundation

enum VyronModelPrecisionLabel {
    static func text(_ precision: String) -> String {
        let normalized = precision.uppercased()
        let floatingPointBits = ["F16": 16, "FP16": 16, "BF16": 16, "F32": 32, "FP32": 32, "F64": 64, "FP64": 64]
        if let bits = floatingPointBits[normalized] { return VyronAppText.settingsPrecisionBits(bits, precision) }
        guard let family = normalized.range(of: #"\A(?:Q|IQ)[1-8](?:_|\z)"#, options: .regularExpression) else {
            return precision
        }
        let prefix = String(normalized[family]).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        guard let bit = prefix.last, bit.isNumber else { return precision }
        return VyronAppText.settingsPrecisionBits(bit.wholeNumberValue ?? 0, precision)
    }
}
