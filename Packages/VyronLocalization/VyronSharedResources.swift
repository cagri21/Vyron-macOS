import Foundation

enum VyronSharedResources {
    private static let bundleName = "Vyron_VyronLocalization.bundle"

    static let current: VyronLocalizedBundle = {
        if let url = Bundle.main.resourceURL?.appendingPathComponent(bundleName), let bundle = Bundle(url: url) {
            return VyronLocalizedBundle(bundle)
        }
        return VyronLocalizedBundle(.module)
    }()
}
