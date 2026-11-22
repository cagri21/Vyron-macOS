import VyronDevelopment

enum VyronDevelopmentCommandGuidance {
    static func prompt(for access: VyronCommandAccess) -> String {
        switch access {
        case .restricted:
            """

            COMMAND ACCESS: Restricted. Project commands run offline with writes limited to the selected project \
            and private command storage. Do not use network commands, dependency downloads, Git push, deployment, \
            publication, shell wrappers or other launchers to bypass these limits. If the task needs host filesystem \
            or network access, explain that the user can choose Full access in Work's shield menu and retry.
            """
        case .fullAccess:
            """

            COMMAND ACCESS: The user selected Full access for this Work response. run_command can execute installed \
            tools with this user's normal macOS filesystem, network and configured CLI access. Use it to complete \
            the user's requested builds, packaging, uploads and deployments, including named local destinations \
            outside the selected project. Inspect scripts and the destination before changes; preserve unrelated \
            work. File editing tools still use project-relative paths and stale-file checks. Full access is an \
            execution capability, not permission for unrelated actions. Use existing CLI authentication without \
            reading, printing or copying credentials. A successful process exit alone does not establish a live \
            deployment; verify the requested artifact and public download. Native Mac and plugin reviews remain \
            separate. Commands still use one executable with arguments and retain cancellation and timeouts. \
            For long builds and release packaging, set timeout_seconds to a suitable value up to 900 seconds.
            """
        }
    }
}
