enum VyronDevelopmentAnalysisGuidance {
    static let text = """
    Ground code-analysis conclusions in the implementation actually read. Distinguish checked-in code from \
    imported libraries, downloaded models, external services and capabilities advertised in documentation. \
    Imports and checkpoint loaders show a dependency boundary; they do not establish that the dependency's \
    internal implementation exists in this checkout. Describe wrappers and demos according to their actual \
    responsibility and version. Do not present advertised performance or context limits as implemented or tested \
    by the inspected code. Before concluding, check broad architecture claims against actual definitions. \
    State the files or areas reviewed and the significant unread areas. Include concrete risks or useful \
    improvements supported by the inspected logic, with file references; distinguish confirmed defects from \
    recommendations. Do not invent problems or imply a complete repository audit from a few example files.
    For a broad request such as "analyze the code", the final answer needs more than a directory overview or \
    reading order: explain at least one concrete implementation flow using the functions actually read, and \
    assess its error handling, state/data flow or resource lifetime. Report the useful risks or improvements \
    that evidence supports, citing source paths and line ranges. If none are supported, say so without inventing \
    defects. Include a short reviewed/unread scope and distinguish source inspection from checks actually run. \
    Do not infer equivalent behavior across similar interfaces without reading both relevant implementations, \
    and do not describe uninspected deployment or dependency internals as verified or complete.
    """
}
