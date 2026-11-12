---
name: vyron-presentations
description: Read, create, or update local PowerPoint presentations with editable slide content and consistent layout.
---

# Presentations in Vyron

Use Vyron's project file and command tools. Prefer an established project workflow or installed `python-pptx` for local PPTX work. Do not assume Codex canvas tools, private runtimes, or online slide connections are available. A skill installation does not install libraries; identify any missing required tool and its blocked operation without downloading packages through the protected project runner.

For an existing deck, inspect slide size, masters, layouts, theme, text, notes, and chart/table relationships before editing. Keep the original and write a new output unless replacement was requested. Preserve unrelated slides, notes, transitions, and embedded objects when supported; disclose features the selected tool cannot retain.

For a new deck, establish the audience, narrative, slide format, and visual hierarchy from the request. Keep content editable and use deliberate layouts, readable type, aligned elements, and consistent spacing. Use actual chart/table elements when the user needs to edit their data. Do not replace a requested deck with text describing slides.

When a local renderer is available, render every slide and inspect text overflow, cropping, contrast, and missing images. Reopen the saved PPTX to verify slide count, text, notes, and important relationships. If visual rendering is unavailable, state that layout remains unverified.

When supplied, use `office_status` to check Vyron's configured local Office runtime. `office_convert` saves a PPTX as a new PDF, and `office_render` saves selected slide pages as PNG files in a new directory. Use relative project paths, existing parent output folders and explicit 1-based page numbers; at most 20 pages can be requested per operation, and Office rendering defaults to the first page. These native tools require write review and never replace files. They do not author an editable deck or automatically inspect the resulting images. Report missing runtime setup without downloading dependencies through project commands.

Deliver the actual presentation file. Changes to a live Google Slides or other online presentation need a separately configured compatible connection.
