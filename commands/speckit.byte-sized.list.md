---
description: "List rules grouped by domain and status (human-facing summary)."
scripts:
  sh: ../../scripts/bash/rules-query.sh
  ps: ../../scripts/powershell/rules-query.ps1
---

# /speckit.byte-sized.list

Human-facing overview of the rules graph, grouped by domain and status.

## User Input

$ARGUMENTS

## Steps

1. If `$ARGUMENTS` contains `--status all`, include every status; otherwise default to `active,deprecated` (excluding `draft` and `superseded`). Pass `--include-drafts` when the user explicitly asks for drafts.
2. Call the query script with `--limit 500` (effectively no cap for browsing):
   - Bash: `{SCRIPT_SH} --limit 500 --status <statuses>`
   - PowerShell: `{SCRIPT_PS} -Limit 500 -Status <statuses>`
3. Group the resulting array by `domain`, then by `status`. For each group, emit a markdown bullet list of `id — statement` (statement truncated to 120 chars).
4. End with a totals line: `Total: N rules across M domains (active: A, deprecated: D, superseded: S, draft: K)`.

## Output

A grouped markdown summary. No rationale or bodies.
