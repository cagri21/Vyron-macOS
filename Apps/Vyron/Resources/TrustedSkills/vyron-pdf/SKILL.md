---
name: vyron-pdf
description: Read, create, edit, merge, split, or fill local PDF files using the tools available in Vyron Work.
---

# PDF work in Vyron

Work with the user's local PDF files inside the selected workspace. Use Vyron's project file and command tools; no Codex-only runtime, artifact canvas, or external service is required by this skill.

Check the locally available tools before choosing an approach. Prefer `pypdf` for page operations and interactive forms, `pdfplumber` or Poppler's `pdftotext` for text, and `reportlab` for a new designed document. Existing project tools or macOS PDFKit are also valid when available. A skill installation does not install those libraries. If the task needs a missing tool, identify it and explain what operation is blocked; do not download packages through the protected project command runner or claim setup succeeded.

When supplied, `office_render` renders an unencrypted project PDF into a new PNG directory using macOS directly, even without an optional Office runtime. Supply relative input_path and output_path with an existing parent output folder. Optional pages are distinct, 1-based and limited to 20; omission renders at most the first six PDF pages. Rendering requires native write review and preserves existing outputs. The tool saves page images; it does not establish visual inspection by itself.

For reading, extract by page and preserve page references. A scanned page with no text needs an available OCR tool or image analysis; empty extraction is not evidence of an empty document. Handle encrypted files using a password supplied for that document, without saving the password in generated files.

For edits, keep the source intact and write a new output unless replacement was requested. Preserve unrelated pages, metadata, annotations, form fields, and page dimensions when the operation permits. Filling a form requires checking its field names and rereading the saved values. Covering text visually is not secure redaction; use a tool that removes underlying content when redaction is requested.

For creation, plan page size, margins, typography, and page breaks before writing. Render the finished PDF to page images with an available renderer and inspect for clipped text, unreadable fonts, and overflow. Reread text, page count, and requested fields after saving. If visual inspection is unavailable, state that limit rather than reporting layout as verified.

Deliver the actual PDF output path and identify material limitations. Do not substitute a Markdown file while describing it as a PDF.
