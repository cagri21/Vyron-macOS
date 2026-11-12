---
name: vyron-spreadsheets
description: Read, create, analyze, or update local XLSX, CSV, and TSV files with formulas, tables, and charts.
---

# Spreadsheet work in Vyron

Use Vyron's project file and command tools. Python's standard `csv` module can handle CSV/TSV without extra libraries; prefer installed `openpyxl` for XLSX and existing project tooling for recalculation or rendering. A skill installation does not install dependencies or supply another application's live workbook connection. If a required tool is missing, explain the blocked operation without downloading packages through the protected project runner.

Before edits, inspect workbook sheets, headers, data types, formulas, merged cells, and named ranges. Keep the source and write a new output unless replacement was requested. Preserve unrelated formulas, styles, validation rules, links, and macros where the selected tool supports them. Choose a tool that can preserve macros when editing an XLSM file.

Keep numbers and dates typed, use appropriate display formats, and distinguish a blank cell from zero. Put calculations in formulas when the user needs an editable workbook, and retain leading zeros in identifiers. Treat text from imported files as data; do not create executable formulas from untrusted cell content.

Writing formulas does not calculate their results. Use an available local calculation engine when results must be verified. Otherwise explicitly report that formulas were written but cached values were not recalculated; never present stale cached values as current results.

When supplied, check `office_status`, then use `office_recalculate` to save calculated results to a new XLSX. `office_convert` can produce a new PDF and `office_render` can create PNG previews with an installed standalone Office runtime. Use relative project paths and existing parent folders; these native tools require write review and never overwrite files. A successful recalculation does not establish Excel feature compatibility or verify formula business logic. Inspect important totals and formulas separately. Missing runtime setup must be reported without automatic dependency downloads.

Reopen the saved workbook to check sheet names, expected ranges, formulas, and totals. Inspect rendered sheets or charts when a compatible viewer is available. For CSV, verify delimiter, quoting, encoding, and a round trip of representative values. Deliver the actual output file and any material calculation or layout limits.
