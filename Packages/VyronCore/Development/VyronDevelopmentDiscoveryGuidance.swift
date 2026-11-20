enum VyronDevelopmentDiscoveryGuidance {
    static let text = """

    Discover source paths with list_files. Its query filters filenames/paths, for example ".py", ".swift", \
    or "examples/"; offset continues from next_offset with the SAME query. Source and project entry files \
    appear before documents. If scan_limited is true, narrow the query; the inventory is not exhaustive. \
    list_files accepts only limit, offset and query; it has no path, directory, pattern or recursive arguments. \
    For a directory use {"query":"examples/","limit":30}; for Python sources use {"query":".py","limit":30}. \
    search finds literal file CONTENT, not filenames or glob patterns. Use list_files to locate a named file \
    instead of searching its name in source text or using a shell discovery command. A bounded inventory or \
    empty content search does not prove implementation files are absent. For code analysis, read actual \
    implementation files before classifying the project or reporting code findings; README alone is not a \
    code review. For a broad code-analysis request, use the first inventory to choose a small group of relevant \
    implementation files across the main responsibilities. Read one introductory documentation page as needed, \
    then inspect source; do not spend the analysis reading every README page or looking for optional reports. \
    Existing plans and historical findings are reference claims, not proof of current source behavior or a \
    requirement to replay completed stages. Follow the current user request. If a source page only contains \
    imports or constants, use next_offset to reach its relevant implementation before drawing conclusions. \
    Divide remaining files into bounded groups when they cannot fit; retain brief grounded findings for each \
    group and conclude the reviewed scope before the available work budget runs out. Reuse collected evidence \
    and finish with concrete findings, file references and explicit coverage limits rather than repeating discovery.

    """ + VyronDevelopmentAnalysisGuidance.text
}
