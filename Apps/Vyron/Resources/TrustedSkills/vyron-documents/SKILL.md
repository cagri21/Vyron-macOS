---
name: vyron-documents
description: Read, create, or update local Word documents when DOCX formatting, tables, comments, or tracked changes matter.
---

# Word documents in Vyron

Use Vyron's project file and command tools with the user's local workspace. Prefer an existing document workflow or installed `python-docx`; do not assume another application's private runtime is available. A skill installation does not install libraries. Report a missing required tool and the operation it blocks without downloading packages through the protected project runner.

When supplied, use `office_status` to check Vyron's configured standalone Office runtime. `office_convert` converts a project DOCX into a new PDF, and `office_render` creates PNG page previews in a new directory. These native tools use relative project paths, require an existing parent output folder, preserve existing outputs, and require native write review. Office rendering defaults to page 1; request other 1-based pages explicitly. A missing runtime is a setup limitation, not permission to download packages or bypass the local runner. These tools do not create or edit DOCX content.

Inspect the source document's paragraphs, styles, tables, headers, footers, sections, and relationships before editing. Preserve the original file and create a new output unless replacement is requested. Change the narrowest relevant structures so comments, fields, links, and unrelated formatting survive.

For new documents, use semantic paragraph styles, consistent margins, real headings and lists, and deliberate table widths. Avoid repeated blank paragraphs as a layout mechanism. Use real document elements for page breaks and page numbers.

Comments and tracked changes require appropriate OOXML handling; ordinary paragraph replacement is not tracked editing. Verify relationships, authorship metadata, and the changed text if the request needs redlining. Do not claim tracked changes or comments exist unless they are stored in the output.

When a compatible local renderer is available, render the saved DOCX and inspect page breaks, table overflow, headers, and text clipping. Reread the output's text and tables. If rendering is unavailable, disclose that visual layout remains unverified.

Deliver the saved DOCX file. Online Google Docs changes require a separately configured compatible connection; do not imply a local file was uploaded.
