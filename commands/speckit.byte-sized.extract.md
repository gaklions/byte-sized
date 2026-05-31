---
description: "Extract candidate business bites from a spec or clarification log into the staging area for review."
scripts:
  sh: ../../scripts/bash/bites-extract.sh
  ps: ../../scripts/powershell/bites-extract.ps1
---

# /speckit.byte-sized.extract

Propose candidate business bites from a source document and stage them for the user to review.

This command is **human-gated**: nothing is added to the active graph until the user runs `/speckit.byte-sized.add` (or accepts the staged drafts in-line).

## User Input

$ARGUMENTS

## Steps

1. Resolve the source file:
   - If `$ARGUMENTS` is a path, use it.
   - Else read the `SPECIFY_FEATURE` environment variable to locate the active feature directory and prefer (in order): `spec.md`, `clarify.md`, `plan.md`. If none exist, ask the user for an explicit path and stop.
   - Capture the feature id (parent directory name) for the `--feature` flag.
2. **Read the source file** and propose candidate bites. Each candidate must be a single sentence in declarative form ("must / must not / always / never"), with a guess at `domain` (from the configured domain list — see `byte-sized-config.yml`) and 3–6 lowercase `tags`. Avoid duplicating phrasing already covered by existing bites (run `/speckit.byte-sized.query --text "<key phrase>"` first if the spec is large).
3. Format the candidates as a YAML array:
   ```yaml
   - statement: "..."
     domain: "..."
     tags: ["...", "..."]
     rationale: "..."
   - statement: "..."
     ...
   ```
4. Pipe the YAML to the extract script:
   - Bash: `printf '%s' "$candidates" | {SCRIPT_SH} --source-file <path> --feature <feature-id>`
   - PowerShell: `$candidates | {SCRIPT_PS} -SourceFile <path> -Feature <feature-id>`
5. The script de-duplicates against the existing index and writes survivors to `.specify/bites/_drafts/<feature>-<timestamp>.yml`. It prints `{drafts_file, kept, dropped_as_duplicate}`.
6. Display the survivors to the user as a numbered list (statement + proposed domain + proposed tags). Ask:
   > "Promote which drafts? (`all`, comma-separated numbers, or `none` to leave staged)"
7. For each accepted draft, invoke `/speckit.byte-sized.add` programmatically with the draft's fields (do **not** require the user to re-type). Each promotion runs its own conflict pre-check.
8. Report a summary: `Extracted N candidate(s); kept M after dedup; promoted P; left K staged in <drafts_file>.`

## Notes for hooks

When invoked via the `after_specify` or `after_clarify` hook, the agent should run steps 1–5 silently and then stop after step 6 — the user prompt is the human gate. Hook execution must not auto-promote.

## Output

A short summary (counts) plus the list of new bite ids if any drafts were promoted.
