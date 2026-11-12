public struct VyronModelThinkingLevels: Equatable, Sendable {
    public let levels: [VyronModelThinkingLevel]
    public let supportsOn: Bool
    public let supportsOff: Bool

    public var hasControls: Bool { !levels.isEmpty || supportsOn || supportsOff }

    public init(
        levels: [VyronModelThinkingLevel],
        supportsOn: Bool = false,
        supportsOff: Bool = false
    ) {
        self.levels = VyronModelThinkingLevel.allCases.filter(levels.contains)
        self.supportsOn = supportsOn
        self.supportsOff = supportsOff
    }
}
