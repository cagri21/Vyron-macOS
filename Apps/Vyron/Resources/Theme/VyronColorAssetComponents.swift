import SwiftUI

struct VyronColorAssetComponents: Decodable {
    let red: String
    let green: String
    let blue: String
    let alpha: String

    func resolved() throws -> Color {
        guard let red = Double(red), let green = Double(green), let blue = Double(blue), let alpha = Double(alpha),
            [red, green, blue, alpha].allSatisfy({ $0.isFinite && (0...1).contains($0) })
        else { throw VyronColorAssetError.invalidComponents }
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
