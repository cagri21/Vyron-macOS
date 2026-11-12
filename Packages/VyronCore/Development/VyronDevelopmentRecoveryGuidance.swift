enum VyronDevelopmentRecoveryGuidance {
    static let outputLimit = """
    The previous inference reached its output limit before completing a usable response. No tool call from that \
    incomplete response was executed. Continue the SAME original task with the same model and request limits. \
    Use smaller file edits and tool batches instead of generating a large file or several files in one response. \
    Re-read current files before editing. Preserve all user guidance, completed action records, Plan-mode \
    restrictions, and command approvals; do not repeat saved actions. Return concise complete text or valid native \
    tool calls. If the remaining work cannot fit the available budget, report it honestly as unfinished.
    """

    static let continuation = """
    This work cycle has ended; the SAME user task remains active. Continue its unfinished work automatically \
    using the saved checkpoint and original user guidance. Re-read current files before editing, retain completed \
    stages, and do not replay completed or declined actions. The build/test allowance has NOT reset. Complete the \
    remaining stages and verify source changes before finishing. If a real blocker remains, explain it accurately.
    """

    static let verification = """
    Verification still lacks a current successful local build or test. Continue the SAME task and run an \
    appropriate permitted check before finishing. Re-read files if needed; do not rewrite completed work. Respect \
    refusals and the remaining build/test allowance. If checking is unavailable or blocked, explain that limitation \
    and leave the task unfinished; do not claim success.
    """

    static func stagnation(tools: [String]) -> String {
        """
        The last tool round made no new progress. Repeated or unsuccessful actions: \(tools.joined(separator: ", ")). \
        Choose a different approach to the remaining task; do not repeat unchanged reads, identical writes, or \
        refused commands. Use the actual tool failures and checkpoint to revise the plan or perform the next \
        useful action. If discovery is repeating, stop listing the same folder or varying find filters. For a \
        folder analysis, read a small number of relevant documents or representative files that have not been \
        read, then answer using the collected evidence. Generic setup README/PLANS files may not describe the \
        folder's actual purpose; use substantive project documents when available. If enough evidence is already \
        available, return the findings now and state any limits. An analysis request does not require edits or a \
        build. A new plan explanation alone is not progress. Preserve the original user scope, approvals, \
        completed action records, and verification requirements. If blocked, explain the concrete blocker.
        """
    }
}
