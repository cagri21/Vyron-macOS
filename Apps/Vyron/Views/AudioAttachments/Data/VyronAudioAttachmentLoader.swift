import AudioToolbox
import Darwin
import Foundation
import OSLog
import UniformTypeIdentifiers
import VyronModelDomain

actor VyronAudioAttachmentLoader {
    static let acceptedTypes: [UTType] = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
    private static let knownExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aiff", "aif", "aifc", "aac", "caf", "flac"
    ]
    private static let logger = Logger(subsystem: "ai.vyron.desktop", category: "Audio attachment")

    private let transcribe: @Sendable (URL) async -> String?

    init(transcribe: @escaping @Sendable (URL) async -> String? = VyronAudioAttachmentTranscriber.transcribe) {
        self.transcribe = transcribe
    }

    static func supports(filename: String) -> Bool {
        let pathExtension = (filename as NSString).pathExtension.lowercased()
        return !pathExtension.isEmpty && (knownExtensions.contains(pathExtension)
            || UTType(filenameExtension: pathExtension)?.conforms(to: .audio) == true)
    }

    func load(_ url: URL) async throws -> VyronFileAttachment {
        try Task.checkCancellation()
        guard url.isFileURL else { throw VyronAudioAttachmentError.unreadable }
        let data = try read(url)
        return try await load(data, name: url.lastPathComponent)
    }

    func load(_ data: Data, name: String) async throws -> VyronFileAttachment {
        try Task.checkCancellation()
        guard data.count <= VyronAudioAttachmentLimits.maximumImportBytes else {
            throw VyronAudioAttachmentError.tooLarge
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VyronAudio-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { removeStagedAudio(directory) }
        let pathExtension = (name as NSString).pathExtension
        let file = pathExtension.isEmpty
            ? directory.appendingPathComponent("Audio")
            : directory.appendingPathComponent("Audio").appendingPathExtension(pathExtension)
        guard FileManager.default.createFile(
            atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]
        ) else { throw VyronAudioAttachmentError.unreadable }
        let duration = try validatedDuration(file)
        let transcript: String?
        if duration <= VyronAudioAttachmentLimits.maximumTranscriptionSeconds {
            transcript = await transcribe(file)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            transcript = nil
        }
        try Task.checkCancellation()
        let text = transcript.flatMap { $0.isEmpty ? nil : $0 }
        let excerpt = text.map { boundedAgentPrefix($0, bytes: VyronAudioAttachmentLimits.maximumTranscriptBytes) }
        let info = VyronFileAttachmentInfo(name: name, kind: .audio, duration: duration)
        return VyronFileAttachment(info: info, text: excerpt, isTruncated: excerpt != text)
    }

    private func read(_ url: URL) throws -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw VyronAudioAttachmentError.unreadable }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw VyronAudioAttachmentError.unreadable
        }
        let limit = VyronAudioAttachmentLimits.maximumImportBytes
        guard info.st_size <= limit else { throw VyronAudioAttachmentError.tooLarge }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        guard let data = try handle.read(upToCount: limit + 1) else {
            throw VyronAudioAttachmentError.unreadable
        }
        return data
    }

    private func validatedDuration(_ url: URL) throws -> TimeInterval {
        var opened: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &opened) == noErr, let file = opened else {
            throw VyronAudioAttachmentError.unreadable
        }
        defer { AudioFileClose(file) }

        var duration: Float64 = 0
        var durationSize = UInt32(MemoryLayout<Float64>.size)
        var audioBytes: UInt64 = 0
        var audioBytesSize = UInt32(MemoryLayout<UInt64>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyEstimatedDuration, &durationSize, &duration) == noErr,
            AudioFileGetProperty(file, kAudioFilePropertyAudioDataByteCount, &audioBytesSize, &audioBytes) == noErr,
            duration.isFinite, duration > 0, audioBytes > 0
        else { throw VyronAudioAttachmentError.unreadable }
        return duration
    }

    private func removeStagedAudio(_ directory: URL) {
        do { try FileManager.default.removeItem(at: directory) }
        catch { Self.logger.error("Could not remove a staged audio attachment.") }
    }
}
