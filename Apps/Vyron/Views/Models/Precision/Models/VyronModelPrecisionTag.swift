import VyronModelDomain

enum VyronModelPrecisionTag {
    static func matches(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second else { return false }
        return ModelCatalog.sameInstalledName(first.lowercased(), second.lowercased())
    }
}
