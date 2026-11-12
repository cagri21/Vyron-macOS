enum VyronModelCatalogRefresh {
    case unchanged
    case loaded
    case failed(VyronModelCatalogFailure)
}
