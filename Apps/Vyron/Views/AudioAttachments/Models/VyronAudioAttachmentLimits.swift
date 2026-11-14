enum VyronAudioAttachmentLimits {
    static let maximumImportMiB = 20
    static let maximumImportBytes = maximumImportMiB * 1_024 * 1_024
    static let maximumTranscriptionSeconds = 60.0
    static let maximumTranscriptBytes = 4_000
    static let transcriptionTimeout = Duration.seconds(30)
}
