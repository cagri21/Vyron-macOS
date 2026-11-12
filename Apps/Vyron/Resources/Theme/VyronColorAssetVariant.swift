import Foundation

struct VyronColorAssetVariant: Decodable {
    let idiom: String
    let color: VyronColorAssetValue
    let appearances: [VyronColorAssetAppearance]?
}
