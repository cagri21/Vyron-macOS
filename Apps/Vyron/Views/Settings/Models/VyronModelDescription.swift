import VyronCore

enum VyronModelDescription {
    static func summary(_ descriptor: ModelDescriptor) -> String {
        switch descriptor.tag {
        case "qwen3.8:27b": VyronAppText.settingsQwen38Summary
        case "qwen3.6:35b": VyronAppText.settingsQwen36Summary
        case "devstral-small-2:24b": VyronAppText.settingsDevstralSummary
        case "qwen3-coder:30b": VyronAppText.settingsQwenCoderSummary
        case "qwen3-coder-next:q4_K_M": VyronAppText.settingsQwenNextSummary
        case "qwen3:4b": VyronAppText.settingsQwenHelperSummary
        default: descriptor.summary.replacingOccurrences(of: " and vision", with: "")
        }
    }

    static func memoryNote(_ descriptor: ModelDescriptor) -> String {
        switch descriptor.tag {
        case "qwen3.8:27b": VyronAppText.settingsQwen38Memory
        case "qwen3.6:35b": VyronAppText.settingsQwen36Memory
        case "devstral-small-2:24b": VyronAppText.settingsDevstralMemory
        case "qwen3-coder:30b": VyronAppText.settingsQwenCoderMemory
        case "qwen3-coder-next:q4_K_M": VyronAppText.settingsQwenNextMemory
        case "qwen3:4b": VyronAppText.settingsQwenHelperMemory
        default: descriptor.memoryNote
        }
    }
}
