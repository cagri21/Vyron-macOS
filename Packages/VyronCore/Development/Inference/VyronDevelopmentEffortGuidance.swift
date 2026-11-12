enum VyronDevelopmentEffortGuidance {
    static func prompt(for effort: AgentEffort, delegationAvailable: Bool) -> String {
        let guidance: String
        switch effort {
        case .automatic, .balanced:
            guidance = "Handle routine feature work and normal debugging with focused inspection and relevant validation."
        case .quick:
            guidance = "Prefer a fast, contained approach for obvious tasks. Inspect what is needed and verify the change."
        case .deep:
            guidance = "Investigate complex failures and multi-file effects. Check assumptions and production risks."
        case .extraHigh:
            guidance = """
                Examine security boundaries, architecture dependencies and migration compatibility where relevant to \
                the task. Check failure paths and preserve existing data and contracts.
                """
        case .maximum:
            guidance = """
                Focus deeply on the hardest single problem. Compare plausible causes or approaches, verify the \
                decisive evidence, and check the result against the original goal.
                """
        case .ultra:
            guidance = delegationAvailable
                ? """
                    Coordinate large work by identifying independent read-only research or review questions. Use \
                    the existing parallel_tasks tool only when independent work materially helps, within its \
                    \(VyronParallelTaskLimits.maximumTasks)-helper limit. Integrate findings before dependent actions; \
                    do not invent parallel tasks \
                    or delegate work simply to consume a budget.
                    """
                : """
                    Complete this focused assignment with careful analysis and a clear result for the coordinating \
                    task. Delegation is unavailable in this run.
                    """
        }
        return "\nEffort guidance: \(guidance) Existing execution, permission and verification limits still apply."
    }
}
