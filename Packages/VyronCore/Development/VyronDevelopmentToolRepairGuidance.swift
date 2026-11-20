import VyronModelDomain

/// Internal model feedback; the original localized error remains the user-facing failure.
enum VyronDevelopmentToolRepairGuidance {
    static func suffix(for error: any Error, call: DevelopmentToolCall) -> String? {
        guard let agentError = error as? DevelopmentAgentError, case .invalidTool = agentError else { return nil }
        let guidance: String
        switch call.function.name {
        case "list_files":
            guidance = """
            list_files accepts only limit, offset and query, all optional. limit is an integer from 1 to 300; \
            offset is an integer from 0 to 2000. query is a nonempty literal filename/path substring up to \
            500 UTF-8 bytes, not a glob. To list a directory, use {"query":"examples/","limit":30}; to find \
            Python sources, use {"query":".py","limit":30}. Do not send path, directory, pattern or recursive. \
            Continue with the returned next_offset and the same query.
            """
        case "read_file":
            guidance = """
            read_file accepts only path and offset. path is required and must be a project-relative file path; \
            offset is an optional integer UTF-8 byte offset, default 0. Example: \
            {"path":"examples/demo/cli_demo.py","offset":0}. Use an observed path from list_files, then use \
            read_file's returned next_offset for later pages. Do not send start_line, end_line, limit or directory.
            """
        case "search":
            guidance = """
            search accepts only query and limit. query is required, nonempty literal file CONTENT up to \
            500 UTF-8 bytes; limit is an optional integer from 1 to 60, default 30. Example: \
            {"query":"def ","limit":30}. For a filename or directory use list_files with query instead. \
            Do not send path, directory, pattern, regex or recursive.
            """
        default:
            return nil
        }
        return """


        Tool argument repair: \(guidance)
        Correct argument shape only; existing project, secret-path and action permissions still apply. \
        If the failure refused a path or permission, keep that refusal and do not retry it through another tool.
        """
    }
}
