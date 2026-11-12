import CryptoKit
import Darwin
import Foundation

public struct DevelopmentFile: Identifiable, Codable, Sendable {
    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public let path: String
    public let size: Int64
}

public struct DevelopmentChange: Identifiable, Codable, Sendable {
    public let id: UUID
    public let path: String
    public let before: String?
    public let after: String
    public let unifiedDiff: String
}

public struct CommandRequest: Codable, Sendable {
    public let command: String
    public let timeout: TimeInterval
    public init(command: String, timeout: TimeInterval = 120) {
        self.command = command
        self.timeout = timeout
    }
}

public struct CommandResult: Identifiable, Codable, Sendable {
    public let id: UUID
    public let command: String
    public let exitCode: Int32
    public let output: String
    public let timedOut: Bool
    public let truncated: Bool
    public let duration: TimeInterval
    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

public struct DevelopmentError: Error, LocalizedError, Sendable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

private struct DevelopmentJournal: Codable {
    let schemaVersion: Int
    let rootPath: String
    let changes: [DevelopmentChange]
}

public actor DevelopmentWorkspace {
    public nonisolated let rootURL: URL
    public nonisolated let taskStateDirectoryURL: URL
    private let rootFD: Int32
    private let storage: URL
    private let journalURL: URL
    private var readHashes: [String: String] = [:]
    private var observedHashes: [String: String] = [:]
    private var observedText: [String: String] = [:]
    private var pending: [String: DevelopmentChange] = [:]
    private var writtenHashes: [String: String] = [:]
    private var commandRunning = false
    private var fileOperations: VyronProjectFileOperations?
    private static let maximumFileBytes = 512_000
    private static let excluded: Set<String> = [
        ".git", ".build", ".swiftpm", "node_modules", "vendor", "pods", "carthage", "build", "dist", "deriveddata",
        "__pycache__", "venv", ".venv", "target", "output", "secrets", "credentials"
    ]
    private static let hiddenAllowed: Set<String> = [
        ".gitignore", ".editorconfig", ".swiftlint.yml", ".swiftformat", ".prettierrc"
    ]
    private static let secretExtensions: Set<String> = [
        "env", "pem", "key", "p12", "pfx", "cer", "crt", "der", "mobileprovision", "keystore", "jks", "sqlite",
        "sqlite3", "db", "log"
    ]
    private static let secretNames: Set<String> = [
        "credentials", "credentials.json", "secrets", "secrets.json", "secrets.swift", "auth.json", "tokens.json",
        "token.json", "service-account.json", "google-services.json", "googleservice-info.plist", "id_rsa", "id_ed25519"
    ]

    public init(rootURL: URL) throws {
        let values = try rootURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .canonicalPathKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw DevelopmentError("Choose an existing project folder, not a symbolic link.")
        }
        let canonical = URL(
            fileURLWithPath: values.canonicalPath ?? rootURL.resolvingSymlinksInPath().path,
            isDirectory: true
        )
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
        guard canonical.path != "/", canonical.path != home.path,
            !["/Users", "/System", "/Library", "/Applications", "/private", "/private/tmp"].contains(canonical.path)
        else { throw DevelopmentError("Choose a specific project folder.") }
        let descriptor = open(canonical.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw DevelopmentError("The project folder could not be opened safely.") }
        self.rootURL = canonical
        self.rootFD = descriptor
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let run =
            applicationSupport
            .appendingPathComponent("VyronAI/DevelopmentRuns/" + UUID().uuidString, isDirectory: true)
        let projects = applicationSupport.appendingPathComponent("VyronAI/DevelopmentProjects", isDirectory: true)
        let projectStorage = projects.appendingPathComponent(Self.hash(Data(canonical.path.utf8)), isDirectory: true)
        self.journalURL = projectStorage.appendingPathComponent("changes.json")
        self.taskStateDirectoryURL = projectStorage.appendingPathComponent("TaskStates", isDirectory: true)
        do {
            try FileManager.default.createDirectory(
                at: run,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: run.path)
            self.storage = run
            for directory in [projects, projectStorage] {
                if (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                    throw DevelopmentError("Project history storage must not be a symbolic link.")
                }
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o700]
                )
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            }
            if (try? journalURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw DevelopmentError("Project history must not be a symbolic link.")
            }
            if FileManager.default.fileExists(atPath: journalURL.path) {
                let journal = try JSONDecoder().decode(DevelopmentJournal.self, from: Data(contentsOf: journalURL))
                guard journal.schemaVersion == 1, journal.rootPath == canonical.path,
                    Set(journal.changes.map(\.path)).count == journal.changes.count
                else {
                    throw DevelopmentError(
                        "Project history has an invalid version, root or duplicate file paths. The existing history was preserved."
                    )
                }
                for change in journal.changes {
                    let parts = change.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
                    guard !change.path.hasPrefix("/"), change.path.utf8.count <= 4_096,
                        !parts.isEmpty, parts.allSatisfy(Self.allowedComponent),
                        change.after.utf8.count <= Self.maximumFileBytes,
                        (change.before?.utf8.count ?? 0) <= Self.maximumFileBytes
                    else {
                        throw DevelopmentError(
                            "Project history contains an unsafe file path or oversized source file. The existing history was preserved."
                        )
                    }
                    pending[change.path] = change
                    writtenHashes[change.path] = Self.hash(Data(change.after.utf8))
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
            }
            let operations = try VyronProjectFileOperations(
                rootURL: canonical,
                journalDirectory: projectStorage.appendingPathComponent("FileOperations", isDirectory: true),
                isAllowedComponent: Self.allowedComponent
            )
            fileOperations = operations
            let restored = try Self.reconciledFileOperationChanges(Array(pending.values), operations: operations)
            if restored.didChange {
                pending = Dictionary(uniqueKeysWithValues: restored.changes.map { ($0.path, $0) })
                writtenHashes = Dictionary(uniqueKeysWithValues: restored.changes.map {
                    ($0.path, Self.hash(Data($0.after.utf8)))
                })
                let journal = DevelopmentJournal(schemaVersion: 1, rootPath: canonical.path, changes: restored.changes)
                try JSONEncoder().encode(journal).write(to: journalURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
            }
        } catch {
            close(descriptor)
            throw error
        }
    }

    deinit { close(rootFD) }

    public func listFiles(limit: Int = 300) throws -> [DevelopmentFile] {
        let cap = min(max(1, limit), 2_000)
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
            )
        else { throw DevelopmentError("The project could not be listed.") }
        var files: [DevelopmentFile] = []
        var visited = 0
        let prefix = rootURL.path + "/"
        for case let url as URL in enumerator {
            visited += 1
            if visited > 20_000 || files.count >= cap { break }
            let values = try url.resourceValues(forKeys: [
                .isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey
            ])
            if values.isSymbolicLink == true { continue }
            if values.isDirectory == true {
                if !Self.allowedComponent(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, Self.allowedComponent(url.lastPathComponent),
                url.path.hasPrefix(prefix), (values.fileSize ?? 0) <= Self.maximumFileBytes
            else { continue }
            let path = String(url.path.dropFirst(prefix.count))
            files.append(DevelopmentFile(path: path, size: Int64(values.fileSize ?? 0)))
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    public func beginTaskReadScope() {
        readHashes.removeAll()
        observedHashes.removeAll()
        observedText.removeAll()
        fileOperations?.discardPreparedReviews()
    }

    public func readFile(path: String, maxBytes: Int = 40_000, forEditing: Bool = true) throws -> String {
        let data = try readData(path: path)
        guard let data else { throw DevelopmentError("The file does not exist: \(path)") }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw DevelopmentError("This file is not supported UTF-8 source text.")
        }
        let cap = min(max(maxBytes, 1), Self.maximumFileBytes)
        if forEditing {
            observedHashes[path] = Self.hash(data)
            observedText[path] = Self.utf8Prefix(data, cap: cap)
            if data.count <= cap { readHashes[path] = Self.hash(data) } else { readHashes.removeValue(forKey: path) }
        }
        if data.count <= cap {
            return text
        }
        return Self.utf8Prefix(data, cap: cap) + "\n[Excerpt truncated. Read the full file before replacing it.]"
    }

    public func search(query: String, limit: Int = 40) throws -> String {
        guard !query.isEmpty, query.count <= 500 else {
            throw DevelopmentError("Use a nonempty search query under 500 characters.")
        }
        var lines: [String] = []
        for file in try listFiles(limit: 150) {
            guard let data = try? readData(path: file.path), !data.contains(0),
                let text = String(data: data.prefix(40_000), encoding: .utf8)
            else { continue }
            for (index, line) in text.components(separatedBy: .newlines).enumerated()
            where line.localizedCaseInsensitiveContains(query) {
                lines.append("\(file.path):\(index + 1): \(String(line.prefix(400)))")
                if lines.count >= min(max(limit, 1), 100) { return lines.joined(separator: "\n") }
            }
        }
        return lines.isEmpty ? "No matches in the bounded project search." : lines.joined(separator: "\n")
    }

    public func fileMatches(path: String, content: String) throws -> Bool {
        try Task.checkCancellation()
        return try readData(path: path) == Data(content.utf8)
    }

    public func fileMatchesRecordedHash(path: String, contentHash: String) throws -> Bool {
        try Task.checkCancellation()
        guard let data = try readData(path: path) else { return false }
        return Self.hash(data) == contentHash
    }

    public func writeFile(path: String, content: String) throws -> DevelopmentChange {
        try Task.checkCancellation()
        let data = Data(content.utf8)
        guard data.count <= Self.maximumFileBytes, !data.contains(0) else {
            throw DevelopmentError("Source writes must be UTF-8 text under 512 KB.")
        }
        let old = try readData(path: path)
        if let old {
            guard readHashes[path] == Self.hash(old) else {
                throw DevelopmentError(
                    "Read the complete current file before editing. It may have changed since the previous read: \(path)"
                )
            }
        }
        let initial: String?
        if let prior = pending[path] {
            initial = prior.before
        } else {
            initial = old.flatMap { String(data: $0, encoding: .utf8) }
        }
        if let old, String(data: old, encoding: .utf8) == nil {
            throw DevelopmentError("Binary files cannot be replaced by the agent.")
        }
        if pending[path] == nil {
            let backup = storage.appendingPathComponent(
                Self.hash(Data(path.utf8)) + "-" + UUID().uuidString + ".original"
            )
            if let old {
                try old.write(to: backup, options: .atomic);
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            }
        }
        try atomicWrite(path: path, data: data)
        readHashes[path] = Self.hash(data)
        observedHashes[path] = Self.hash(data)
        observedText[path] = content
        writtenHashes[path] = Self.hash(data)
        let change = DevelopmentChange(
            id: pending[path]?.id ?? UUID(),
            path: path,
            before: initial,
            after: content,
            unifiedDiff: Self.diff(path: path, before: initial, after: content)
        )
        pending[path] = change
        do { try persistChanges() } catch {
            throw DevelopmentError(
                "The file was written, but its change history could not be saved: \(error.localizedDescription)"
            )
        }
        return change
    }

    public func validateUnchangedEdit(path: String, fragment: String) throws {
        try Task.checkCancellation()
        guard !fragment.isEmpty, let current = try readData(path: path),
            observedHashes[path] == Self.hash(current), observedText[path]?.contains(fragment) == true,
            let text = String(data: current, encoding: .utf8) else {
            throw DevelopmentError("Read the current file and choose text present in the excerpt before editing.")
        }
        guard text.components(separatedBy: fragment).count == 2 else {
            throw DevelopmentError("The old text must match exactly once. Include more surrounding source lines.")
        }
    }

    public func editFile(path: String, oldText: String, newText: String) throws -> DevelopmentChange {
        try Task.checkCancellation()
        guard !oldText.isEmpty, let current = try readData(path: path),
            observedHashes[path] == Self.hash(current),
            observedText[path]?.contains(oldText) == true,
            let text = String(data: current, encoding: .utf8)
        else {
            throw DevelopmentError("Read the current file and choose text present in the excerpt before editing.")
        }
        let pieces = text.components(separatedBy: oldText)
        guard pieces.count == 2 else {
            throw DevelopmentError("The old text must match exactly once. Include more surrounding source lines.")
        }
        let completeRead = readHashes[path] != nil
        let excerpt = observedText[path] ?? ""
        readHashes[path] = Self.hash(current)
        defer { if !completeRead { readHashes.removeValue(forKey: path) } }
        let change = try writeFile(path: path, content: pieces[0] + newText + pieces[1])
        if !completeRead { observedText[path] = excerpt.replacingOccurrences(of: oldText, with: newText) }
        return change
    }

    public func changes() -> [DevelopmentChange] { pending.values.sorted { $0.path < $1.path } }

    public func configureFileTrash(_ adapter: any VyronProjectFileTrashing) throws {
        guard !commandRunning, let fileOperations else {
            throw DevelopmentError("Wait for the current project command before configuring file operations.")
        }
        fileOperations.configureTrash(adapter)
    }

    public func prepareFileOperation(
        _ request: VyronProjectFileOperationRequest
    ) throws -> VyronPreparedProjectFileOperation {
        try Task.checkCancellation()
        guard !commandRunning, let fileOperations else {
            throw DevelopmentError("Wait for the current project command before changing file locations.")
        }
        let prepared = try fileOperations.prepare(request)
        if let destination = prepared.destinationPath {
            let destinationImpact = VyronProjectFileOperationImpact(
                paths: .init(sourcePath: destination, destinationPath: nil),
                affectedFilePaths: [], isCaseSensitive: prepared.isCaseSensitive
            )
            if pending.keys.contains(where: destinationImpact.containsSource) {
                throw DevelopmentError(
                    "The destination has existing change history. Inspect it before moving another item there."
                )
            }
        }
        return prepared
    }

    public func performFileOperation(
        _ prepared: VyronPreparedProjectFileOperation
    ) throws -> VyronProjectFileOperationResult {
        try Task.checkCancellation()
        guard !commandRunning, let fileOperations else {
            throw DevelopmentError("Wait for the current project command before changing file locations.")
        }
        let archived = pending.values.filter { prepared.impact.containsSource($0.path) }
        do {
            let result = try fileOperations.perform(prepared, archivedChanges: archived)
            try reconcileFileOperationChanges()
            beginTaskReadScope()
            return result
        } catch {
            beginTaskReadScope()
            do { try reconcileFileOperationChanges() } catch {
                throw DevelopmentError(
                    "The file operation needs inspection: its change history could not be reconciled. Do not repeat it."
                )
            }
            throw error
        }
    }

    public func fileOperationDisposition(
        _ prepared: VyronPreparedProjectFileOperation
    ) -> VyronProjectFileOperationDisposition {
        fileOperations?.disposition(prepared) ?? .uncertain
    }

    public func fileOperationRecovery(id: UUID) throws -> VyronProjectFileOperationRecovery {
        guard let fileOperations else {
            return VyronProjectFileOperationRecovery(
                disposition: .uncertain, result: nil, recordedAt: .distantPast, preservedItemURL: nil
            )
        }
        return try fileOperations.recovery(id: id)
    }

    private func reconcileFileOperationChanges() throws {
        guard let fileOperations else { return }
        let restored = try Self.reconciledFileOperationChanges(Array(pending.values), operations: fileOperations)
        guard restored.didChange else { return }
        pending = Dictionary(uniqueKeysWithValues: restored.changes.map { ($0.path, $0) })
        writtenHashes = Dictionary(uniqueKeysWithValues: restored.changes.map {
            ($0.path, Self.hash(Data($0.after.utf8)))
        })
        try persistChanges()
    }

    private static func reconciledFileOperationChanges(
        _ changes: [DevelopmentChange],
        operations: VyronProjectFileOperations
    ) throws -> VyronProjectFileChangesReconciliation {
        var pending = Dictionary(uniqueKeysWithValues: changes.map { ($0.path, $0) })
        var changed = false
        for record in try operations.journal.records() where try operations.shouldReconcile(record) {
            let operation = record.identity.operation
            let impact = operation.impact
            for original in record.archivedChanges where pending[original.path]?.id == original.id {
                pending.removeValue(forKey: original.path)
                if let path = impact.relocatedPath(original.path) {
                    let destinationImpact = VyronProjectFileOperationImpact(
                        paths: .init(sourcePath: path, destinationPath: nil),
                        affectedFilePaths: [], isCaseSensitive: operation.isCaseSensitive
                    )
                    let components = path.split(separator: "/").count
                    let conflicting = pending.values.contains {
                        $0.id != original.id && $0.path.split(separator: "/").count == components
                            && destinationImpact.containsSource($0.path)
                    }
                    guard !conflicting else {
                        throw DevelopmentError("Moved change history conflicts with another saved edit; both were preserved.")
                    }
                    pending[path] = DevelopmentChange(
                        id: original.id, path: path, before: original.before, after: original.after,
                        unifiedDiff: Self.diff(path: path, before: original.before, after: original.after)
                    )
                }
                changed = true
            }
        }
        return VyronProjectFileChangesReconciliation(
            changes: pending.values.sorted { $0.path < $1.path }, didChange: changed
        )
    }

    public func revert(path: String) throws {
        try Task.checkCancellation()
        guard let change = pending[path], let current = try readData(path: path),
            Self.hash(current) == writtenHashes[path]
        else {
            throw DevelopmentError(
                "The file changed after the agent's edit. Your changes were preserved; inspect it before reverting."
            )
        }
        if let original = change.before {
            try atomicWrite(path: path, data: Data(original.utf8))
            readHashes[path] = Self.hash(Data(original.utf8))
        } else {
            let (parent, leaf) = try parentDescriptor(path: path, create: false)
            defer { close(parent) }
            try Task.checkCancellation()
            guard unlinkat(parent, leaf, 0) == 0 else {
                throw DevelopmentError("The new file could not be removed safely.")
            }
            readHashes.removeValue(forKey: path)
        }
        pending.removeValue(forKey: path)
        writtenHashes.removeValue(forKey: path)
        do { try persistChanges() } catch {
            throw DevelopmentError(
                "The file was reverted, but its change history could not be saved: \(error.localizedDescription)"
            )
        }
    }

    private func persistChanges() throws {
        guard (try? journalURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw DevelopmentError("Project history must not be a symbolic link.")
        }
        let journal = DevelopmentJournal(
            schemaVersion: 1,
            rootPath: rootURL.path,
            changes: pending.values.sorted { $0.path < $1.path }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(journal).write(to: journalURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
    }

    public nonisolated static func approvalRequirement(command: String) -> String? {
        CommandPolicy.approvalRequirement(command: command)
    }

    public nonisolated static func validateCommand(_ command: String) throws {
        try CommandPolicy.validate(CommandPolicy.arguments(command))
    }

    public func runCommand(
        _ command: String,
        timeout: TimeInterval = 120,
        approved: Bool = false,
        onOutput: @escaping @Sendable (String) -> Void
    ) async throws -> CommandResult {
        try Task.checkCancellation()
        guard !commandRunning else { throw DevelopmentError("Wait for the current project command to finish.") }
        let argv = try CommandPolicy.arguments(command)
        try CommandPolicy.validate(argv)
        if let reason = Self.approvalRequirement(command: command), !approved { throw DevelopmentError(reason) }
        guard timeout.isFinite, timeout > 0, timeout <= 900 else {
            throw DevelopmentError("Command timeout must be between 0 and 900 seconds.")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else {
            throw DevelopmentError("macOS execution protection is unavailable. No command was run.")
        }
        let executable = try CommandPolicy.executable(argv[0], arguments: Array(argv.dropFirst()), root: rootURL)
        if !approved, !CommandPolicy.isTrustedDevelopmentTool(executable) {
            throw DevelopmentError("Review commands that use a custom executable before running them.")
        }
        let root = rootURL
        let run = storage.appendingPathComponent("commands/" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: run,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        commandRunning = true
        defer { commandRunning = false }
        let state = CommandState()
        return try await withTaskCancellationHandler {
            try await Task.detached {
                try GuardedCommand.run(
                    command: command,
                    executable: executable,
                    arguments: Array(argv.dropFirst()),
                    root: root,
                    storage: run,
                    timeout: timeout,
                    state: state,
                    onOutput: onOutput
                )
            }.value
        } onCancel: {
            state.cancel()
        }
    }

    private static func allowedComponent(_ component: String) -> Bool {
        let lower = component.lowercased()
        return !component.isEmpty && component != "." && component != ".." && !component.contains("\0")
            && !excluded.contains(lower) && (!component.hasPrefix(".") || hiddenAllowed.contains(lower))
            && !secretNames.contains(lower) && !lower.hasPrefix(".env") && !lower.hasPrefix("credentials.")
            && !lower.hasPrefix("secrets.")
            && !secretExtensions.contains(URL(fileURLWithPath: component).pathExtension.lowercased())
    }

    private func parentDescriptor(path: String, create: Bool) throws -> (Int32, String) {
        guard !path.hasPrefix("/"), path.utf8.count <= 4_096 else {
            throw DevelopmentError("Use a relative path inside the selected project.")
        }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy(Self.allowedComponent) else {
            throw DevelopmentError(
                "Secret files, generated folders, hidden paths and parent-directory traversal are excluded."
            )
        }
        var parent = dup(rootFD)
        guard parent >= 0 else { throw DevelopmentError("The project folder is unavailable.") }
        do {
            for part in parts.dropLast() {
                if create, mkdirat(parent, part, 0o755) != 0, errno != EEXIST {
                    throw DevelopmentError("Could not create the source folder.")
                }
                let next = openat(parent, part, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw DevelopmentError("This path is unavailable or contains a symbolic link.") }
                close(parent); parent = next
            }
            return (parent, parts.last!)
        } catch { close(parent); throw error }
    }

    private func readData(path: String) throws -> Data? {
        let pair: (Int32, String)
        do { pair = try parentDescriptor(path: path, create: false) } catch {
            // New nested paths may not have parent folders yet. Validate every component first.
            let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !path.hasPrefix("/"), !parts.isEmpty, parts.allSatisfy(Self.allowedComponent) else { throw error }
            if !FileManager.default.fileExists(
                atPath: rootURL.appendingPathComponent(path).deletingLastPathComponent().path
            ) {
                return nil
            }
            throw error
        }
        defer { close(pair.0) }
        let file = openat(pair.0, pair.1, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else {
            if errno == ENOENT { return nil }
            throw DevelopmentError("The file is unavailable or is a symbolic link.")
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size <= Self.maximumFileBytes else {
            throw DevelopmentError("Only regular project files under 512 KB can be read or changed.")
        }
        let handle = FileHandle(fileDescriptor: file, closeOnDealloc: false)
        let data = try handle.read(upToCount: Self.maximumFileBytes + 1) ?? Data()
        guard data.count <= Self.maximumFileBytes else { throw DevelopmentError("This project file is too large.") }
        return data
    }

    private func atomicWrite(path: String, data: Data) throws {
        let (parent, leaf) = try parentDescriptor(path: path, create: true)
        defer { close(parent) }
        var existing = stat()
        let exists = fstatat(parent, leaf, &existing, AT_SYMLINK_NOFOLLOW) == 0
        if exists, existing.st_mode & S_IFMT != S_IFREG {
            throw DevelopmentError("Only regular files can be replaced.")
        }
        let temporary = ".vyron-write-" + UUID().uuidString
        let descriptor = openat(
            parent,
            temporary,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            exists ? existing.st_mode & 0o777 : 0o644
        )
        guard descriptor >= 0 else { throw DevelopmentError("A safe source write could not be created.") }
        defer { close(descriptor); unlinkat(parent, temporary, 0) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try Task.checkCancellation()
        guard renameat(parent, temporary, parent, leaf) == 0 else {
            throw DevelopmentError("The source file could not be replaced atomically.")
        }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private static func utf8Prefix(_ data: Data, cap: Int) -> String {
        let prefix = data.prefix(cap)
        for trim in 0...min(3, prefix.count) {
            if let text = String(data: prefix.dropLast(trim), encoding: .utf8) { return text }
        }
        return ""
    }
    private static func diff(path: String, before: String?, after: String) -> String {
        guard before != after else { return "" }
        func lines(_ text: String) -> [String] {
            if text.isEmpty { return [] }
            var lines = text.components(separatedBy: "\n")
            if text.hasSuffix("\n") { lines.removeLast() }
            return lines
        }
        let old = lines(before ?? ""), new = lines(after)
        return
            "--- \(before == nil ? "/dev/null" : "a/" + path)\n+++ b/\(path)\n@@ -\(old.isEmpty ? 0 : 1),\(old.count) +\(new.isEmpty ? 0 : 1),\(new.count) @@\n"
            + old.map { "-" + $0 + "\n" }.joined() + new.map { "+" + $0 + "\n" }.joined()
    }
}
