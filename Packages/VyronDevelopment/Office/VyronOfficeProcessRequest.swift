import Foundation

/// A native-owned executable invocation. Model input never supplies executable arguments.
public struct VyronOfficeProcessRequest: Sendable {
    public let executable: URL
    public let arguments: [String]
    public let directory: URL

    public init(executable: URL, arguments: [String], directory: URL) {
        self.executable = executable
        self.arguments = arguments
        self.directory = directory
    }
}
