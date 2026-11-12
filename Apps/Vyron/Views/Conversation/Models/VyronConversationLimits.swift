enum VyronConversationLimits {
    static let maximumMessageBytes = 12_000
    static let maximumAttachedFiles = 6
    static let maximumAttachedFileBytes = 16_000
    static let maximumWorkspaceSummaryFiles = 80
    static let messageOverheadBytes = 80
    static let compactedSubmissionOverheadBytes = 200
    static let folderSubmissionOverheadBytes = 400
    static let folderImportOverheadBytes = 200
    static let skillContextOverheadBytes = 200
}
