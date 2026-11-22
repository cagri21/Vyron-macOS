struct VyronCommandInvocation: Sendable {
    let request: VyronCommandRequest
    let executable: String
    let arguments: [String]
    let directories: VyronCommandDirectories
}
