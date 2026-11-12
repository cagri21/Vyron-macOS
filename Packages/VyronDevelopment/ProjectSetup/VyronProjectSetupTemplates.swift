enum VyronProjectSetupTemplates {
    static func files(context: VyronProjectSetupContext) -> [VyronProjectSetupFile] {
        [
            VyronProjectSetupFile(path: "AGENTS.md", contents: agents(context: context)),
            VyronProjectSetupFile(path: "README.md", contents: readme(context: context)),
            VyronProjectSetupFile(path: "PLANS.md", contents: plans),
            VyronProjectSetupFile(path: ".gitignore", contents: gitignore(context: context))
        ]
    }

    private static func agents(context: VyronProjectSetupContext) -> String {
        """
        # Project instructions

        These instructions apply to this folder and its descendants. More specific
        `AGENTS.md` instructions in a subfolder apply to work in that subfolder.

        ## Getting started

        - Read `README.md` and relevant manifests before making changes.
        - \(manifestGuidance(context: context))
        - Confirm setup and check commands from the repository; do not assume they exist.

        ## Working conventions

        - Keep changes within the requested scope and preserve unrelated work.
        - Follow the project's existing architecture, naming, and formatting conventions.
        - Keep secrets and credentials out of source, prompts, and logs.
        - Use `PLANS.md` for a multi-step task and keep its progress and checks current.
        - Run relevant documented checks when possible. Report actual results and any blockers.
        - Update documentation when behavior or setup changes.
        - Commit, publish, or deploy only when the user requests it.

        ## Project-specific knowledge

        Add verified build/test commands, important constraints, and durable decisions here.
        Do not record guesses as established project facts.

        """
    }

    private static func readme(context: VyronProjectSetupContext) -> String {
        """
        # \(context.projectName)

        Add the project's purpose and current behavior here.

        ## Setup

        \(manifestGuidance(context: context))

        Inspect the project configuration and existing scripts before documenting exact
        prerequisites, setup steps, and local build/test commands. No setup commands have
        been run by creating this file.

        ## Working in this project

        - Read `AGENTS.md` for project instructions.
        - Use `PLANS.md` to record a multi-step task, its progress, and verification.
        - Keep this README aligned with the project's actual setup and behavior.

        """
    }

    private static let plans = """
        # Project plans

        Use this document for a multi-step task. Record the actual request before planning;
        creating this file does not mean any work has been requested or completed.

        ## Goal and scope

        Describe the requested outcome, constraints, and what is outside the task.

        ## Steps

        Add small, reviewable steps and mark them complete only after their work is done.

        ## Progress and decisions

        Record useful findings, material decisions, and any unresolved blockers.

        ## Verification

        Record commands actually run, their results, and any checks that remain blocked.

        """

    private static func manifestGuidance(context: VyronProjectSetupContext) -> String {
        guard !context.manifests.isEmpty else {
            return "No supported root manifest was detected. Inspect the source and existing documentation first."
        }
        let names = context.manifests.map { "`\($0)`" }.joined(separator: ", ")
        return "Detected root configuration: \(names). Inspect it before choosing setup or check commands."
    }

    private static func gitignore(context: VyronProjectSetupContext) -> String {
        var lines = ["# Local operating-system metadata", ".DS_Store"]
        if context.manifests.contains("Package.swift") {
            lines += ["", "# Swift package build output", ".build/", ".swiftpm/"]
        }
        if context.manifests.contains("package.json") {
            lines += ["", "# JavaScript dependencies", "node_modules/"]
        }
        if context.manifests.contains("pyproject.toml") || context.manifests.contains("requirements.txt") {
            lines += ["", "# Python environments and bytecode", ".venv/", "__pycache__/", "*.py[cod]"]
        }
        if context.manifests.contains("Cargo.toml") {
            lines += ["", "# Rust build output", "target/"]
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
