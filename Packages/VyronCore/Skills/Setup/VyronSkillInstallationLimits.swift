enum VyronSkillInstallationLimits {
    static let maximumEntries = 1_024
    static let maximumDepth = 10
    static let maximumFileBytes = 8 * 1_024 * 1_024
    static let maximumPackageBytes = 32 * 1_024 * 1_024
    static let maximumPathBytes = 2_048
    static let copyChunkBytes = 16_384
}
