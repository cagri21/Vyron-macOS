import Foundation
import VyronModelDomain

extension ModelSourceClient {
    public static func canDiscoverPrecisionVariants(for installedModel: LocalModel) -> Bool {
        precisionIdentity(for: installedModel)?.libraryURL != nil
    }

    public func discoverPrecisionVariants(for installedModel: LocalModel) async throws -> [ModelSourceVariant] {
        guard let identity = Self.precisionIdentity(for: installedModel), let url = identity.libraryURL else { return [] }
        let variants: [ModelSourceVariant]
        do {
            variants = try await discover(url: url)
        } catch ModelSourceError.noVariants {
            return []
        } catch ModelSourceError.httpStatus(404) {
            return []
        }

        return variants.filter { variant in
            guard let tag = variant.ollamaTag, variant.quantization != nil,
                !ModelCatalog.sameInstalledName(tag, installedModel.name),
                let suffix = Self.variantSuffix(in: tag)
            else { return false }
            return Self.precisionVariantIdentity(suffix) == identity.variant
        }
    }

    public static func installedPrecisionVariants(
        for installedModel: LocalModel,
        among models: [LocalModel]
    ) -> [ModelSourceVariant] {
        guard let identity = precisionIdentity(for: installedModel) else { return [] }
        let installedSize = installedModel.parameterSize.flatMap { parameterSize(in: $0) }
        let hasTaggedSize = parameterSize(in: identity.variant) != nil
        return models.compactMap { model -> ModelSourceVariant? in
            guard !ModelCatalog.sameInstalledName(model.name, installedModel.name),
                precisionIdentity(for: model) == identity,
                let quantization = model.quantization ?? variantSuffix(in: model.name).flatMap({ precision(in: $0) })
            else { return nil }
            if !hasTaggedSize, let installedSize,
                let candidateSize = model.parameterSize.flatMap({ parameterSize(in: $0) }),
                installedSize != candidateSize {
                return nil
            }
            return ModelSourceVariant(
                id: model.name,
                name: model.name,
                ollamaTag: model.name,
                quantization: quantization,
                parameterSize: model.parameterSize,
                sizeBytes: model.size > 0 ? model.size : nil
            )
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func precisionIdentity(for model: LocalModel) -> VyronOllamaPrecisionIdentity? {
        guard VyronLocalModelTag.isValid(model.name) else { return nil }
        let libraryPrefix = "library/"
        let name = model.name.lowercased()
        let libraryName = name.hasPrefix(libraryPrefix) ? String(name.dropFirst(libraryPrefix.count)) : name
        guard let family = libraryName.split(separator: ":").first else { return nil }

        let installedSuffix = variantSuffix(in: libraryName) ?? "latest"
        let comparisonSuffix: String
        if installedSuffix == "latest" {
            let canonicalSuffix = ModelCatalog.descriptor(for: libraryName).flatMap { variantSuffix(in: $0.tag) }
            guard let suffix = canonicalSuffix ?? model.parameterSize.flatMap({ parameterSize(in: $0) }) else {
                return nil
            }
            comparisonSuffix = suffix
        } else {
            comparisonSuffix = installedSuffix
        }
        return VyronOllamaPrecisionIdentity(family: String(family), variant: precisionVariantIdentity(comparisonSuffix))
    }

    private static func variantSuffix(in tag: String) -> String? {
        tag.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init)
    }

    private static func precisionVariantIdentity(_ suffix: String) -> String {
        // Strip known precision and runtime markers while retaining size and tuning markers.
        let precision = #"(?:IQ[1-4](?:_XXS|_XS|_S|_M|_NL)?|TQ[12](?:_0)?|Q[2-9](?:_[01]|_K(?:_[SML])?)?)"#
        let format = #"(?:BF16|FP16|F16|FP32|F32|INT[48]|MXFP[48]|NVFP4)"#
        let pattern = "(?i)(?<![a-z0-9])(?:\(precision)|\(format)|mlx)(?![a-z0-9])"
        return suffix.replacingOccurrences(of: pattern, with: "-", options: .regularExpression)
            .lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).joined(separator: "-")
    }
}
