enum VyronAutoLocalLimits {
    static let maximumCandidates = 32
    static let maximumIdentifierBytes = 256
    static let maximumModelNameBytes = 512
    static let maximumParameterDescriptionBytes = 128
    static let maximumCapabilityCount = 16
    static let maximumCapabilityBytes = 64
    static let maximumMessageCount = 8
    static let conversationBytes = 8_192
    static let referenceBytes = 2_048
    static let catalogBytes = 8_192
    // Includes the encoded chat envelope, leaving space for transport overhead and a quick response in 32K.
    static let maximumPromptBytes = 24_576
    static let minimumConversationBytes = 1_024
    static let minimumReferenceBytes = 256
    static let maximumResponseBytes = 4_096
}
